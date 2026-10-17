import CoolifyAPI
import Foundation
import HotifySSH

/// Finds the server a resource runs on, signs in with this device's key, finds the container, and runs a shell in it.
///
/// The device key stays in memory from the unlock until a shell opens, so setup steps in between don't ask again.
/// The next session asks anew.
@Observable
final class TerminalModel {
    enum Phase: Equatable {
        case locating
        /// Coolify rules the terminal out here, such as for a server behind a Cloudflare Tunnel.
        case unavailable(String)
        case unlocking
        case connecting
        /// First contact, or a key that differs from the trusted one.
        case trustHost(SSHHostKey, previous: SSHHostKey?)
        /// The server turned the device key down.
        case needsKey
        case choosing([DockerContainer])
        /// A shell runs, or ran, in the canvas.
        case running
        case failed(String)
    }

    let target: TerminalTarget
    private(set) var phase: Phase = .locating
    private(set) var server: Server?
    /// Coolify's address, or the one typed in its place.
    private(set) var address: SSHAddress?
    private(set) var hasOverride = false
    private(set) var container: DockerContainer?
    private(set) var publicKeyLine: String?
    private(set) var isInstalling = false
    private(set) var installProblem: String?
    /// Whether the failure is one a different address could fix.
    private(set) var offersAddress = false
    /// Set once the shell ends, while its output stays on screen.
    private(set) var ending: String?
    /// Changes for every shell, so each starts on a clean canvas.
    private(set) var session = 0

    private let client: CoolifyClient?
    private let hostKeys: HostKeyStore
    private let overrides: AddressOverrides
    private var identity: SSHIdentity?
    private var connection: SSHConnection?
    private var terminal: SSHTerminal?
    private var reader: Task<Void, Never>?
    private var size = (columns: 80, rows: 24)
    /// Output that arrived before the canvas was ready for it.
    private var pending: [UInt8] = []
    private var sink: (([UInt8]) -> Void)?

    init(
        client: CoolifyClient?,
        target: TerminalTarget,
        hostKeys: HostKeyStore = HostKeyStore(),
        overrides: AddressOverrides = AddressOverrides()
    ) {
        self.client = client
        self.target = target
        self.hostKeys = hostKeys
        self.overrides = overrides
    }

    /// For previews: a screen already at `phase`, with nothing behind it.
    init(previewing target: TerminalTarget, phase: Phase, server: Server?, publicKeyLine: String? = nil) {
        client = nil
        self.target = target
        hostKeys = HostKeyStore()
        overrides = AddressOverrides()
        self.phase = phase
        self.server = server
        address = server.flatMap { $0.sshAddress(instanceURL: URL(string: "https://coolify.example.com")!) }
        self.publicKeyLine = publicKeyLine
    }

    /// Who the shell signs in as, and where, such as `root@203.0.113.9`.
    var destination: String? {
        guard let server, let address else { return nil }
        let port = address.port == 22 ? "" : ":\(address.port)"
        return "\(server.sshUser)@\(address.host)\(port)"
    }

    /// Whether the install step can work: Coolify named the key it connects with.
    var canInstall: Bool { client != nil && server?.privateKeyUUID != nil }

    func start() async {
        guard let client else {
            // A preview starts at a later step, which stays.
            if phase == .locating {
                phase = .failed("Hotify has no connection to this instance.")
            }
            return
        }
        phase = .locating
        do {
            let server = try await locate(client)
            self.server = server
            if server.settings?.isTerminalEnabled == false {
                phase = .unavailable(
                    "Coolify has the terminal turned off for \(server.name). Turn it on under the server's Security "
                        + "settings in Coolify.")
                return
            }
            if await isTunneled(server, client) {
                phase = .unavailable("Terminal doesn't support servers behind a Cloudflare Tunnel yet.")
                return
            }
            let override = overrides.address(for: server.uuid)
            hasOverride = override != nil
            address = override ?? server.sshAddress(instanceURL: client.apiBaseURL)
            guard address != nil else {
                offersAddress = true
                phase = .failed("Coolify has no address for \(server.name). Enter the one this device can reach.")
                return
            }
        } catch {
            phase = .failed((error as? CoolifyError)?.summary ?? error.localizedDescription)
            return
        }
        await connect()
    }

    /// Signs in, then looks for the container. Asks for the owner first unless a setup step already did.
    func connect() async {
        guard let server, let address else {
            await start()
            return
        }
        offersAddress = false
        ending = nil
        do {
            publicKeyLine = try DeviceKey.publicKeyLine()
            if identity == nil {
                phase = .unlocking
                identity = try await DeviceKey.unlock(reason: DeviceKey.reason("open a terminal on \(server.name)"))
            }
        } catch {
            phase = Self.phase(for: error as? DeviceKeyError)
            return
        }
        guard let identity else { return }

        phase = .connecting
        do {
            let connection = try await SSHConnection.open(
                host: address.host,
                port: address.port,
                user: server.sshUser,
                identity: identity,
                trusting: hostKeys.key(for: server.uuid)
            )
            await self.connection?.close()
            self.connection = connection
            try await findContainers(on: connection, server: server)
        } catch let error as SSHConnectionError {
            switch error {
            case .hostKeyUnknown(let key):
                phase = .trustHost(key, previous: nil)
            case .hostKeyChanged(let presented, let trusted):
                phase = .trustHost(presented, previous: trusted)
            case .authenticationFailed:
                installProblem = nil
                phase = .needsKey
            case .unreachable, .timedOut:
                offersAddress = true
                phase = .failed(Self.unreachable(server, address, timedOut: error == .timedOut))
            case .channelRejected, .closed:
                phase = .failed("\(server.name) closed the connection.")
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Trusts the key on screen, then connects again.
    func trustPresentedKey() async {
        guard case .trustHost(let key, _) = phase, let server else { return }
        hostKeys.trust(key, for: server.uuid)
        await connect()
    }

    /// Signs in once with the key Coolify connects with, adds this device's key for the same user, then connects with
    /// it. Coolify's key lives only inside this call.
    func installDeviceKey() async {
        guard let client, let server, let address, let line = publicKeyLine, let keyUUID = server.privateKeyUUID,
            !isInstalling
        else { return }
        isInstalling = true
        installProblem = nil
        defer { isInstalling = false }
        do {
            try await DeviceKey.confirmOwner(
                reason: DeviceKey.reason("use Coolify's key to add this device's key to \(server.name)"))
            let material = try await client.privateKeyMaterial(uuid: keyUUID)
            guard let text = material.privateKey else {
                installProblem =
                    "Coolify didn't share its key with this API token. Add the key by hand, or use a token with "
                    + "the read:sensitive permission."
                return
            }
            let coolify = try SSHIdentity(openSSHPrivateKey: text)
            let installer = try await SSHConnection.open(
                host: address.host,
                port: address.port,
                user: server.sshUser,
                identity: coolify,
                trusting: hostKeys.key(for: server.uuid)
            )
            let result = try await installer.run(TerminalCommand.installKey(line))
            await installer.close()
            guard result.exitStatus == 0 else {
                let said = Self.firstLine(result.errorOutput).map { " It said: \($0)" } ?? ""
                installProblem = "\(server.name) didn't take the key.\(said)"
                return
            }
        } catch DeviceKeyError.cancelled {
            return
        } catch let error as SSHKeyError {
            installProblem = Self.describe(error, server: server)
            return
        } catch SSHConnectionError.authenticationFailed {
            installProblem = "\(server.name) turned down Coolify's key too. Add the key by hand instead."
            return
        } catch let error as CoolifyError {
            installProblem = error.summary
            return
        } catch {
            installProblem = "Hotify couldn't add the key: \(error.localizedDescription)"
            return
        }
        await connect()
    }

    /// Opens the shell in one container, on the connection already signed in.
    func open(_ container: DockerContainer) async {
        guard let connection, let server else { return }
        self.container = container
        phase = .connecting
        do {
            let terminal = try await connection.openTerminal(
                TerminalCommand.shell(inContainer: container.name, usesSudo: server.needsSudo),
                columns: size.columns,
                rows: size.rows
            )
            self.terminal = terminal
            identity = nil
            pending = []
            ending = nil
            session += 1
            phase = .running
            reader = Task { [weak self] in
                var status: Int?
                for await output in terminal.output {
                    switch output {
                    case .bytes(let bytes): self?.deliver(bytes)
                    case .exited(let code): status = code
                    }
                }
                await self?.finish(status: status)
            }
        } catch {
            phase = .failed("\(server.name) wouldn't open a shell in \(Self.title(of: container, target: target)).")
        }
    }

    /// Saves the address, or goes back to Coolify's with `nil`, and connects to it.
    func setAddress(_ address: SSHAddress?) async {
        guard let server, let client else { return }
        overrides.set(address, for: server.uuid)
        hasOverride = address != nil
        self.address = address ?? server.sshAddress(instanceURL: client.apiBaseURL)
        await connect()
    }

    // MARK: The canvas

    /// The canvas calls this once it can draw. Output from before then arrives at once.
    func attach(_ sink: @escaping ([UInt8]) -> Void) {
        self.sink = sink
        if !pending.isEmpty {
            sink(pending)
            pending = []
        }
    }

    func detach() {
        sink = nil
    }

    func send(_ bytes: [UInt8]) {
        terminal?.send(bytes)
    }

    func resize(columns: Int, rows: Int) {
        size = (columns, rows)
        terminal?.resize(columns: columns, rows: rows)
    }

    /// Ends the session and the connection, and forgets the key.
    func stop() {
        reader?.cancel()
        reader = nil
        terminal?.close()
        terminal = nil
        identity = nil
        let connection = connection
        self.connection = nil
        Task { await connection?.close() }
    }

    // MARK: Steps

    /// The server that runs the resource. Coolify's resource lists don't name it, so each server is asked what it runs
    /// unless there is only one.
    private func locate(_ client: CoolifyClient) async throws -> Server {
        let servers = try await client.servers().filter { $0.settings?.isBuildServer != true }
        var found = servers.count == 1 ? servers.first?.uuid : nil
        if found == nil {
            for server in servers {
                let resources = (try? await client.resources(onServer: server.uuid)) ?? []
                if resources.contains(where: { $0.uuid == target.route.uuid }) {
                    found = server.uuid
                    break
                }
            }
        }
        guard let found else {
            throw TerminalProblem("Hotify couldn't find the server that runs \(target.resourceName).")
        }
        return try await client.server(found)
    }

    /// The flag usually comes with the server's settings. When it doesn't, the tunnel endpoint says.
    private func isTunneled(_ server: Server, _ client: CoolifyClient) async -> Bool {
        if let flag = server.settings?.isCloudflareTunnel {
            return flag
        }
        return (try? await client.cloudflareTunnel(uuid: server.uuid))?.isCloudflareTunnel ?? false
    }

    private func findContainers(on connection: SSHConnection, server: Server) async throws {
        let lookup = ContainerLookup(owner: owner, uuid: target.route.uuid, usesSudo: server.needsSudo)
        let result = try await connection.run(lookup.command)
        var containers = lookup.containers(in: result.output)
        if let name = target.containerName {
            containers = containers.filter { $0.name == name }
        }
        switch containers.count {
        case 0:
            if let said = Self.firstLine(result.errorOutput), result.exitStatus != 0 {
                phase = .failed("Docker on \(server.name) didn't answer. It said: \(said)")
            } else {
                let name = target.containerTitle ?? target.resourceName
                phase = .failed("\(name) has no running container on \(server.name). Start it, then try again.")
            }
        case 1:
            await open(containers[0])
        default:
            phase = .choosing(containers)
        }
    }

    private func deliver(_ bytes: [UInt8]) {
        if let sink {
            sink(bytes)
        } else {
            pending += bytes
        }
    }

    private func finish(status: Int?) async {
        guard terminal != nil else { return }
        terminal = nil
        let name = server?.name ?? "The server"
        switch status {
        case 0?: ending = "The shell exited."
        case let code?: ending = "The shell exited with status \(code)."
        case nil: ending = "The connection to \(name) closed."
        }
        await connection?.close()
        connection = nil
    }

    private var owner: ContainerOwner {
        switch target.route {
        case .application: .application
        case .database: .database
        case .service: .service
        }
    }

    // MARK: Words

    /// A container's name for people. Coolify names an application's container after its uuid and a timestamp,
    /// which reads as the resource. A service's or compose app's container starts with its own name, then the uuid.
    static func title(of container: DockerContainer, target: TerminalTarget) -> String {
        let uuid = target.route.uuid
        if container.name.hasPrefix(uuid) {
            return target.resourceName
        }
        if let range = container.name.range(of: "-" + uuid), range.lowerBound > container.name.startIndex {
            return String(container.name[..<range.lowerBound])
        }
        return target.containerTitle ?? container.name
    }

    private static func phase(for error: DeviceKeyError?) -> Phase {
        switch error {
        case .cancelled?:
            return .failed("The terminal needs \(UnlockMethod.current().titleWithFallback) to use this device's key.")
        case .noPasscode?:
            return .unavailable(
                "Set a \(UnlockMethod.secretName) on this \(UnlockMethod.deviceName) to use the terminal. Hotify keeps "
                    + "its SSH key behind it.")
        case .missing?:
            return .failed(
                "This device's key is gone, as happens when the \(UnlockMethod.secretName) changes. Try again.")
        case .keychain(let status)?:
            return .failed("The Keychain didn't open this device's key (\(status)).")
        case nil:
            return .failed("Hotify couldn't read this device's key.")
        }
    }

    private static func unreachable(_ server: Server, _ address: SSHAddress, timedOut: Bool) -> String {
        let place = "\(address.host):\(address.port)"
        return timedOut
            ? "\(server.name) didn't answer at \(place) in time."
            : "Hotify couldn't reach \(server.name) at \(place)."
    }

    private static func describe(_ error: SSHKeyError, server: Server) -> String {
        switch error {
        case .unsupportedType(let type):
            "Coolify connects to \(server.name) with a \(type) key, and Hotify only reads ed25519 keys. Add the key "
                + "by hand instead."
        case .encrypted:
            "Coolify's key for \(server.name) has a passphrase. Add the key by hand instead."
        case .unreadable:
            "Hotify couldn't read Coolify's key for \(server.name). Add the key by hand instead."
        }
    }

    private static func firstLine(_ text: String) -> String? {
        text.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// A plain reason the terminal can't go on.
struct TerminalProblem: LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

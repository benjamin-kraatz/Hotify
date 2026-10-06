import CoolifyAPI
import Foundation

/// What to ask Coolify to do with one compose container.
enum ContainerCommand {
    case start
    case stop
    case restart
}

/// Loads each container's uuid, then starts, stops, or restarts one of them, and remembers what an edit starts from.
@Observable
final class ContainerActions {
    var lookupError: String?
    var actionError: String?
    private(set) var busyUUID: String?
    /// What the busy container was asked to do, so its row can say `Restarting…` until the request returns.
    private(set) var busyCommand: ContainerCommand?
    private var targets: [Target] = []
    /// Edits saved this visit. The lists keep the previous values until the next load, which would reopen a stale form.
    private var savedEdits: [String: ContainerEditorValues] = [:]

    var isBusy: Bool { busyUUID != nil }

    /// Fills an empty uuid when the list endpoints named the same container. Leaves the row alone otherwise.
    func resolved(_ containers: [ContainerSummary]) -> [ContainerSummary] {
        containers.map { container in
            guard container.uuid.isEmpty, let uuid = uuid(matching: container) else { return container }
            var copy = container
            copy.uuid = uuid
            return copy
        }
    }

    func isBusy(_ uuid: String) -> Bool {
        busyUUID == uuid
    }

    func command(runningOn uuid: String) -> ContainerCommand? {
        busyUUID == uuid ? busyCommand : nil
    }

    /// Drops the previous service's uuids and remembered edits. Does not touch the rows the dashboard already showed.
    func reset() {
        targets = []
        savedEdits = [:]
        lookupError = nil
        actionError = nil
        busyUUID = nil
        busyCommand = nil
    }

    /// Reads both lists. The rows stay up while this runs; a failure only explains missing actions.
    func load(client: CoolifyClient, service serviceUUID: String) async {
        do {
            async let applications = client.serviceApplications(serviceUUID)
            async let databases = client.serviceDatabases(serviceUUID)
            let loadedApplications = try await applications
            let loadedDatabases = try await databases
            try Task.checkCancellation()
            targets =
                Self.targets(loadedApplications, isDatabase: false)
                + Self.targets(loadedDatabases, isDatabase: true)
            lookupError = nil
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            lookupError = (error as? CoolifyError)?.summary ?? error.localizedDescription
        }
    }

    func run(
        _ command: ContainerCommand,
        container: ContainerSummary,
        client: CoolifyClient,
        service serviceUUID: String
    ) async {
        let uuid = container.uuid
        guard !uuid.isEmpty, busyUUID == nil else { return }
        busyUUID = uuid
        busyCommand = command
        actionError = nil
        defer {
            busyUUID = nil
            busyCommand = nil
        }
        let role: ServiceContainerRole = container.isDatabase ? .database : .application
        do {
            switch command {
            case .start:
                _ = try await client.startServiceContainer(serviceUUID, role: role, uuid: uuid)
            case .stop:
                _ = try await client.stopServiceContainer(serviceUUID, role: role, uuid: uuid)
            case .restart:
                _ = try await client.restartServiceContainer(serviceUUID, role: role, uuid: uuid)
            }
        } catch is CancellationError {
            return
        } catch {
            actionError = (error as? CoolifyError)?.summary ?? error.localizedDescription
        }
    }

    /// The name, domains, and public access the editor opens with. A save from this visit wins, then the lists.
    func editorValues(for container: ContainerSummary) -> ContainerEditorValues {
        if let saved = savedEdits[Self.editKey(container)] { return saved }
        let match = target(for: container)
        let fqdn = match.flatMap { Self.present($0.fqdn) } ?? Self.present(container.fqdn)
        var domains = ResourceConfiguration.split(fqdn)
        if domains.isEmpty, let link = container.link?.absoluteString, !link.isEmpty {
            domains = [link]
        }
        return ContainerEditorValues(
            name: match.flatMap { Self.present($0.humanName) } ?? container.name,
            domains: domains,
            isPublic: match.flatMap { $0.isPublic } ?? container.isPublic,
            publicPort: match.flatMap { $0.publicPort } ?? container.publicPort
        )
    }

    /// Keeps a successful edit for the next time this container's sheet opens.
    func rememberEdit(_ container: ContainerSummary, _ values: ContainerEditorValues) {
        guard !container.uuid.isEmpty else { return }
        savedEdits[Self.editKey(container)] = values
    }

    private func uuid(matching container: ContainerSummary) -> String? {
        target(for: container)?.uuid
    }

    /// Prefers the loaded row with this uuid. A row whose payload omitted the uuid falls back to the name, then the id.
    private func target(for container: ContainerSummary) -> Target? {
        if !container.uuid.isEmpty {
            let sameUUID = targets.filter { $0.uuid == container.uuid && $0.isDatabase == container.isDatabase }
            if sameUUID.count == 1 { return sameUUID[0] }
        }
        let matches = targets.filter { $0.matches(container) }
        if matches.count == 1 { return matches[0] }
        let listedID = Self.listedID(of: container)
        let sameID = matches.filter { listedID != 0 && $0.id == listedID }
        if sameID.count == 1 { return sameID[0] }
        return nil
    }

    private static func editKey(_ container: ContainerSummary) -> String {
        let role = container.isDatabase ? "database" : "application"
        return "\(role)-\(container.uuid)"
    }

    private static func present(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A database row stores `-id - 1`. Matching uses the id the list decoded.
    private static func listedID(of container: ContainerSummary) -> Int {
        guard container.isDatabase, container.id < 0 else { return container.id }
        return -container.id - 1
    }

    private static func targets(_ items: [ServiceApplication], isDatabase: Bool) -> [Target] {
        items.map {
            Target(
                name: $0.name,
                humanName: $0.humanName,
                id: $0.id,
                uuid: $0.uuid,
                isDatabase: isDatabase,
                fqdn: $0.fqdn,
                isPublic: $0.isPublic,
                publicPort: $0.publicPort
            )
        }
    }
}

/// What the container editor opens with: the row, filled in from the lists when those have loaded.
struct ContainerEditorValues: Hashable {
    var name: String
    var domains: [String]
    var isPublic: Bool
    var publicPort: Int?
}

private struct Target: Hashable {
    var name: String
    var humanName: String?
    var id: Int
    var uuid: String
    var isDatabase: Bool
    var fqdn: String?
    var isPublic: Bool?
    var publicPort: Int?

    /// The list's `name` is the compose service name. The row title may be `humanName` instead.
    func matches(_ container: ContainerSummary) -> Bool {
        guard isDatabase == container.isDatabase, !uuid.isEmpty else { return false }
        let wanted = [container.serviceName, container.name].filter { !$0.isEmpty }
        guard !wanted.isEmpty else { return false }
        if wanted.contains(name) { return true }
        if let humanName, wanted.contains(humanName) { return true }
        return false
    }
}

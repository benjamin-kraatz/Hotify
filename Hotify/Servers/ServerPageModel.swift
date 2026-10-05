import CoolifyAPI
import Foundation

/// What the server page has loaded, and the one write it is waiting on.
@Observable
final class ServerPageModel {
    var settings: DockerCleanupSettings?
    var draft: DockerCleanupSettings?
    var executions: [DockerCleanupExecution] = []
    var proxy: ServerProxy?
    var domains: [ServerDomainGroup] = []
    var error: String?
    var notice: String?
    var hasLoaded = false
    var isLoading = false
    var write: ServerWrite?

    var isBusy: Bool { write != nil }

    var hasCleanupChanges: Bool {
        guard let draft else { return false }
        return draft != settings
    }

    /// Drops what the last server loaded, so a new one does not flash it.
    func prepare(for uuid: String) {
        guard loadedUUID != uuid else { return }
        loadedUUID = uuid
        settings = nil
        draft = nil
        executions = []
        proxy = nil
        domains = []
        error = nil
        notice = nil
        hasLoaded = false
        write = nil
    }

    func refresh(client: CoolifyClient, server uuid: String) async {
        let generation = beginLoad()
        defer {
            if generation == loadGeneration {
                isLoading = false
            }
        }
        do {
            async let settings = client.dockerCleanup(uuid: uuid)
            async let executions = client.dockerCleanupExecutions(uuid: uuid)
            async let proxy = client.serverProxy(uuid: uuid)
            async let domains = client.serverDomains(uuid: uuid)
            let loadedSettings = try await settings
            let loadedExecutions = try await executions
            let loadedProxy = try await proxy
            let loadedDomains = try await domains
            try Task.checkCancellation()
            guard generation == loadGeneration else { return }
            let keepDraft = draft != nil && draft != self.settings
            self.settings = loadedSettings
            if !keepDraft {
                draft = loadedSettings
            }
            self.executions = loadedExecutions
            self.proxy = loadedProxy
            self.domains = loadedDomains
            hasLoaded = true
            error = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration else { return }
            self.error = (error as? CoolifyError)?.message ?? error.localizedDescription
        }
    }

    func validate(client: CoolifyClient, server uuid: String, install: Bool) async {
        let kind: ServerWrite = install ? .install : .validate
        let fallback = install ? "Coolify is installing prerequisites." : "Validation started."
        await perform(kind) {
            let action = try await client.validateServer(uuid: uuid, install: install)
            return action.message ?? fallback
        }
        guard error == nil else { return }
        await refresh(client: client, server: uuid)
    }

    func saveCleanup(client: CoolifyClient, server uuid: String) async {
        guard let draft, hasCleanupChanges else { return }
        await perform(.saveCleanup) {
            let saved = try await client.updateDockerCleanup(uuid: uuid, settings: draft)
            settings = saved
            self.draft = saved
            return "Cleanup settings saved."
        }
    }

    /// Runs cleanup with the delete flags the form is showing, so an off switch does not delete.
    func runCleanup(client: CoolifyClient, server uuid: String) async {
        let volumes = draft?.deleteUnusedVolumes == true
        let networks = draft?.deleteUnusedNetworks == true
        await perform(.runCleanup) {
            let action = try await client.runDockerCleanup(
                uuid: uuid,
                deleteUnusedVolumes: volumes,
                deleteUnusedNetworks: networks
            )
            return action.message ?? "Cleanup started."
        }
        guard error == nil else { return }
        await refresh(client: client, server: uuid)
    }

    func restartProxy(client: CoolifyClient, server uuid: String) async {
        await perform(.restartProxy) {
            let action = try await client.restartServerProxy(uuid: uuid)
            return action.message ?? "Proxy restart queued."
        }
        guard error == nil else { return }
        await refresh(client: client, server: uuid)
    }

    private var loadedUUID: String?
    private var loadGeneration = 0

    private func beginLoad() -> Int {
        loadGeneration += 1
        isLoading = true
        return loadGeneration
    }

    /// Sends one write and does not try it again. A lost response can follow a write Coolify accepted.
    private func perform(_ kind: ServerWrite, _ action: () async throws -> String) async {
        guard write == nil else { return }
        write = kind
        defer { write = nil }
        do {
            notice = try await action()
            error = nil
        } catch is CancellationError {
            return
        } catch let error as CoolifyError {
            notice = nil
            self.error = error.message
        } catch {
            notice = nil
            self.error = "The request could not be confirmed. Check the server before trying again."
        }
    }
}

extension ServerPageModel {
    /// A filled page for previews. Nothing here talks to a server.
    static var sample: ServerPageModel {
        let model = ServerPageModel()
        let settings = DockerCleanupSettings(
            dockerCleanupFrequency: "0 2 * * *",
            dockerCleanupThreshold: 80,
            forceDockerCleanup: false,
            deleteUnusedVolumes: true,
            deleteUnusedNetworks: false,
            disableApplicationImageRetention: false
        )
        model.settings = settings
        model.draft = settings
        model.executions = [
            DockerCleanupExecution(
                uuid: "run-failed",
                status: "failed",
                message: "The disk was still above the threshold when the prune finished.",
                createdAt: "2026-10-01T04:00:00Z",
                finishedAt: "2026-10-01T04:02:00Z"
            ),
            DockerCleanupExecution(
                uuid: "run-ok",
                status: "success",
                message: "Pruned 2 images.",
                createdAt: "2026-09-30T04:00:00Z",
                finishedAt: "2026-09-30T04:01:00Z"
            ),
        ]
        model.proxy = ServerProxy(
            status: "running",
            proxyType: "TRAEFIK",
            redirectEnabled: true,
            redirectUrl: "https://example.com"
        )
        model.domains = [
            ServerDomainGroup(ip: "10.0.0.8", domains: ["app.example.com", "api.example.com"]),
            ServerDomainGroup(ip: "10.0.0.9", domains: ["db.example.com"]),
        ]
        model.hasLoaded = true
        return model
    }
}

/// The write the server page is waiting on.
enum ServerWrite: Equatable {
    case validate
    case install
    case saveCleanup
    case runCleanup
    case restartProxy
}

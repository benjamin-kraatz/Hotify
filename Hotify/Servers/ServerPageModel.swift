import CoolifyAPI
import Foundation

/// What the server page has loaded, and the one write it is waiting on.
@Observable
final class ServerPageModel {
    var settings: DockerCleanupSettings?
    var draft: DockerCleanupSettings?
    var executions: [DockerCleanupExecution] = []
    var proxy: ServerProxy?
    var proxyTypeDraft = ""
    var redirectEnabledDraft = false
    var redirectURLDraft = ""
    /// Compose YAML from the last GET, when Coolify included it. Nil means the file was not returned.
    var returnedConfiguration: String?
    var configurationDraft = ""
    var configurationBaseline = ""
    /// True when this server is the one Coolify itself runs on. The proxy in front of the instance is that server's.
    var isCoolifyHost = false
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

    var hasProxySettingChanges: Bool {
        guard let proxy else { return false }
        let type = trimmed(proxyTypeDraft)
        let typeChanged = !type.isEmpty && type.lowercased() != trimmed(proxy.proxyType).lowercased()
        let redirectChanged = redirectEnabledDraft != (proxy.redirectEnabled ?? false)
        let urlChanged = trimmed(redirectURLDraft) != trimmed(proxy.redirectUrl)
        return typeChanged || redirectChanged || urlChanged
    }

    var hasConfigurationChanges: Bool {
        configurationDraft != configurationBaseline
            && !configurationDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Drops what the last server loaded, so a new one does not flash it.
    func prepare(for uuid: String) {
        guard loadedUUID != uuid else { return }
        loadedUUID = uuid
        settings = nil
        draft = nil
        executions = []
        proxy = nil
        proxyTypeDraft = ""
        redirectEnabledDraft = false
        redirectURLDraft = ""
        returnedConfiguration = nil
        configurationDraft = ""
        configurationBaseline = ""
        isCoolifyHost = false
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
            async let proxy = client.serverProxyReading(uuid: uuid)
            async let domains = client.serverDomains(uuid: uuid)
            async let host = client.server(uuid)
            let loadedSettings = try await settings
            let loadedExecutions = try await executions
            let loadedProxy = try await proxy
            let loadedDomains = try await domains
            let loadedHost: Server?
            do {
                loadedHost = try await host
            } catch is CancellationError {
                return
            } catch {
                // The host flag is a sentence on the proxy section. The page still loads without it.
                loadedHost = nil
            }
            try Task.checkCancellation()
            guard generation == loadGeneration else { return }
            let keepDraft = draft != nil && draft != self.settings
            self.settings = loadedSettings
            if !keepDraft {
                draft = loadedSettings
            }
            self.executions = loadedExecutions
            store(loadedProxy)
            isCoolifyHost = loadedHost?.isCoolifyHost == true
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

    func saveProxy(client: CoolifyClient, server uuid: String) async {
        guard hasProxySettingChanges, let proxy else { return }
        let type = trimmed(proxyTypeDraft)
        let url = trimmed(redirectURLDraft)
        let enabled = redirectEnabledDraft
        let typeChanged = !type.isEmpty && type.lowercased() != trimmed(proxy.proxyType).lowercased()
        let enabledChanged = enabled != (proxy.redirectEnabled ?? false)
        let urlChanged = url != trimmed(proxy.redirectUrl)
        await perform(.saveProxy) {
            let updated = try await client.updateServerProxy(
                uuid: uuid,
                redirectEnabled: enabledChanged ? enabled : nil,
                redirectURL: urlChanged && !url.isEmpty ? url : nil,
                clearRedirectURL: urlChanged && url.isEmpty,
                proxyType: typeChanged ? type : nil
            )
            let saved = ServerProxy(
                status: updated.status ?? proxy.status,
                proxyType: updated.proxyType ?? (typeChanged ? type : proxy.proxyType),
                redirectEnabled: updated.redirectEnabled ?? enabled,
                redirectUrl: urlChanged ? (url.isEmpty ? nil : url) : (updated.redirectUrl ?? proxy.redirectUrl)
            )
            self.proxy = saved
            proxyTypeDraft = saved.proxyType ?? ""
            redirectEnabledDraft = saved.redirectEnabled ?? false
            redirectURLDraft = saved.redirectUrl ?? ""
            return "Proxy settings saved."
        }
        guard error == nil else { return }
        await refresh(client: client, server: uuid)
    }

    func saveProxyConfiguration(client: CoolifyClient, server uuid: String) async {
        let yaml = configurationDraft
        guard yaml != configurationBaseline else { return }
        guard !yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        await perform(.saveProxyConfiguration) {
            _ = try await client.saveServerProxyConfiguration(uuid: uuid, configuration: yaml)
            configurationBaseline = yaml
            return "Proxy configuration saved."
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

    private func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Keeps a draft the user has changed. A file the GET omitted is not shown.
    private func store(_ reading: ServerProxyReading) {
        let proxy = reading.proxy
        let typeEdited =
            self.proxy != nil && trimmed(proxyTypeDraft).lowercased() != trimmed(self.proxy?.proxyType).lowercased()
        let redirectEdited = self.proxy != nil && redirectEnabledDraft != (self.proxy?.redirectEnabled ?? false)
        let urlEdited = self.proxy != nil && trimmed(redirectURLDraft) != trimmed(self.proxy?.redirectUrl)
        let configurationEdited = configurationDraft != configurationBaseline
        self.proxy = proxy
        if !typeEdited {
            proxyTypeDraft = proxy.proxyType ?? ""
        }
        if !redirectEdited {
            redirectEnabledDraft = proxy.redirectEnabled ?? false
        }
        if !urlEdited {
            redirectURLDraft = proxy.redirectUrl ?? ""
        }
        if let configuration = reading.configuration {
            returnedConfiguration = configuration
            if !configurationEdited {
                configurationBaseline = configuration
                configurationDraft = configuration
            }
        } else {
            returnedConfiguration = nil
            if !configurationEdited {
                configurationBaseline = ""
                configurationDraft = ""
            }
        }
    }

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
        model.proxyTypeDraft = "TRAEFIK"
        model.redirectEnabledDraft = true
        model.redirectURLDraft = "https://example.com"
        let compose = "services:\n  proxy:\n    image: example\n"
        model.returnedConfiguration = compose
        model.configurationDraft = compose
        model.configurationBaseline = compose
        model.domains = [
            ServerDomainGroup(ip: "10.0.0.8", domains: ["app.example.com", "api.example.com"]),
            ServerDomainGroup(ip: "10.0.0.9", domains: ["db.example.com"]),
        ]
        model.hasLoaded = true
        return model
    }

    /// The sample proxy, on the server Coolify itself runs on.
    static var proxyOnCoolifyHost: ServerPageModel {
        let model = sample
        model.isCoolifyHost = true
        return model
    }

    /// A loaded proxy whose compose file the token could not read.
    static var proxyFileOmitted: ServerPageModel {
        let model = ServerPageModel()
        model.proxy = ServerProxy(status: "running", proxyType: "nginx", redirectEnabled: false)
        model.proxyTypeDraft = "nginx"
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
    case saveProxy
    case saveProxyConfiguration
    case restartProxy
}

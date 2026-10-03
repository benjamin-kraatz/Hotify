import CoolifyAPI
import Foundation

/// What the Deploy a Version sheet works from: the application's source as Coolify has it now, and the value to put
/// back after deploying once. It also deploys.
@Observable
final class DeployVersionModel {
    private(set) var source: ApplicationSource?
    /// What manual deploys build now, which Deploy Once puts back.
    private(set) var previous: ApplicationVersion?
    private(set) var hasLoaded = false
    private(set) var isDeploying = false
    private(set) var loadError: String?
    var error: String?

    private let client: CoolifyClient?
    private let application: String

    init(client: CoolifyClient?, application: String, source: ApplicationSource? = nil) {
        self.client = client
        self.application = application
        self.source = source
        hasLoaded = source != nil
    }

    /// Reads the application fresh, so Deploy Once puts back what Coolify has now, not what a screen loaded earlier.
    func load() async {
        guard let client else { return }
        do {
            let loaded = try await client.application(application)
            source = ApplicationSource(application: loaded)
            if loaded.isDockerImage {
                previous = .imageTag(loaded.dockerRegistryImageTag ?? "latest")
            } else {
                previous = loaded.pinnedCommit.map(ApplicationVersion.commit) ?? .latestCommit
            }
            loadError = source == nil ? "This application has no repository or image to pick a version from." : nil
        } catch is CancellationError {
            return
        } catch {
            loadError = Self.message(for: error)
        }
        hasLoaded = true
    }

    /// Deploys `version`, then puts the previous value back unless `keepsPinned`. `nil` with `error` set when nothing
    /// queued.
    func deploy(_ version: ApplicationVersion, keepsPinned: Bool) async -> DeployedVersion? {
        guard let client, !isDeploying else { return nil }
        isDeploying = true
        defer { isDeploying = false }
        do {
            let deployed = try await client.deploy(
                application, version: version, restoring: keepsPinned ? nil : previous)
            LocalActions.note(.deployment, .application(application))
            error = nil
            return deployed
        } catch is CancellationError {
            return nil
        } catch {
            self.error = Self.message(for: error)
            return nil
        }
    }

    private static func message(for error: Error) -> String {
        guard let error = error as? CoolifyError else { return error.localizedDescription }
        if error.isForbidden {
            return "This token can't change the application. Give it write access in Coolify under Keys & Tokens."
        }
        return error.summary
    }
}

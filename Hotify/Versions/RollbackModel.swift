import CoolifyAPI
import Foundation

/// The images Coolify kept for one application, and the rollback to one of them.
@Observable
final class RollbackModel {
    /// Newest first, without Coolify's build and preview images. The running one is marked current.
    var images: [RollbackImage] = []
    private(set) var hasLoaded = false
    /// Why the list couldn't load. The last list stays.
    var loadError: String?
    /// Why the last rollback didn't queue.
    var error: String?
    private(set) var isRollingBack = false

    private var client: CoolifyClient?
    private var application: String?
    private var generation = 0

    /// Points the model at a resource. Only an application has images, so any other route leaves it empty.
    func prepare(_ client: CoolifyClient, route: ResourceRoute) {
        generation += 1
        self.client = client
        if case .application(let uuid) = route {
            application = uuid
        } else {
            application = nil
        }
        images = []
        hasLoaded = false
        loadError = nil
        error = nil
        isRollingBack = false
    }

    func load() async {
        guard let client, let application else { return }
        let generation = self.generation
        do {
            let loaded = try await client.rollbackImages(application)
            guard generation == self.generation else { return }
            images = loaded.targets
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == self.generation else { return }
            loadError = Self.message(for: error)
        }
        hasLoaded = true
    }

    /// The kept image a production deployment built, if Coolify still has it.
    func image(for line: DeploymentLine) -> RollbackImage? {
        Self.image(for: line, in: images)
    }

    static func image(for line: DeploymentLine, in images: [RollbackImage]) -> RollbackImage? {
        guard !line.isPreview else { return nil }
        return images.first { $0.matches(commit: line.commitSHA ?? line.commit) }
    }

    /// Queues the rollback and returns the deployment Coolify started, or `nil` with `error` set.
    func rollBack(to image: RollbackImage) async -> String? {
        guard let client, let application, !isRollingBack else { return nil }
        let generation = self.generation
        isRollingBack = true
        defer {
            if generation == self.generation {
                isRollingBack = false
            }
        }
        do {
            let deployment = try await client.rollback(application, to: image.tag)
            LocalActions.note(.deployment, .application(application))
            guard generation == self.generation else { return nil }
            error = nil
            return deployment
        } catch is CancellationError {
            return nil
        } catch {
            guard generation == self.generation else { return nil }
            self.error = Self.message(for: error)
            return nil
        }
    }

    private static func message(for error: Error) -> String {
        (error as? CoolifyError)?.message ?? error.localizedDescription
    }
}

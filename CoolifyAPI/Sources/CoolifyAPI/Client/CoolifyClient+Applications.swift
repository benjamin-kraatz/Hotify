import Foundation

extension CoolifyClient {
    public func applications(tag: String? = nil) async throws -> [Application] {
        var query: [URLQueryItem] = []
        if let tag, !tag.isEmpty {
            query.append(URLQueryItem(name: "tag", value: tag))
        }
        return try await getList("applications", query: query)
    }

    public func application(_ uuid: String) async throws -> Application {
        try await get(applicationPath(uuid))
    }

    /// Changes an application's settings. Nothing deploys. Domains and the health check reach the running app with
    /// its next deployment.
    ///
    /// Coolify answers 409 with `CoolifyError.conflicts` when another resource has a domain, and saves nothing then.
    /// On a server without a proxy it answers 200 but keeps the old domains, so read the application back to check.
    public func updateApplication(_ uuid: String, _ update: ApplicationUpdate) async throws {
        let _: CreatedResource = try await patch(applicationPath(uuid), body: update)
    }

    public func startApplication(
        _ uuid: String,
        force: Bool = false,
        instantDeploy: Bool = false
    ) async throws -> QueuedAction {
        try await post(
            "\(applicationPath(uuid))/start",
            query: [
                URLQueryItem(name: "force", value: Self.flag(force)),
                URLQueryItem(name: "instant_deploy", value: Self.flag(instantDeploy)),
            ]
        )
    }

    public func stopApplication(_ uuid: String, dockerCleanup: Bool = true) async throws -> QueuedAction {
        try await post(
            "\(applicationPath(uuid))/stop",
            query: [URLQueryItem(name: "docker_cleanup", value: Self.flag(dockerCleanup))]
        )
    }

    public func restartApplication(_ uuid: String) async throws -> QueuedAction {
        try await post("\(applicationPath(uuid))/restart")
    }

    public func rollbackImages(_ uuid: String) async throws -> RollbackImages {
        try await get("\(applicationPath(uuid))/rollback-images")
    }

    /// Queues a deployment that runs an image Coolify kept, and returns its UUID. The application's settings stay as
    /// they are, so the next deploy builds the branch head again.
    ///
    /// `tag` is a tag from `rollbackImages`. Coolify answers 422 for one outside `[a-zA-Z0-9._-/]`, and 400 when its
    /// deployment queue is full.
    public func rollback(_ uuid: String, to tag: String) async throws -> String {
        let queued: QueuedAction = try await post(
            "\(applicationPath(uuid))/rollback", body: RollbackRequest(commit: tag))
        guard let deployment = queued.deploymentUUID, !deployment.isEmpty else {
            throw CoolifyError(message: queued.message ?? "Coolify did not queue the rollback.")
        }
        return deployment
    }

    public func applicationLogs(
        _ uuid: String,
        window: LogWindow = .lines(100),
        showTimestamps: Bool = false
    ) async throws -> String {
        try await logs("\(applicationPath(uuid))/logs", window: window, showTimestamps: showTimestamps)
    }

    /// Queues a deployment for an existing preview.
    ///
    /// Coolify 4.3 has no restart-only route for previews. `startPreview` and `restartPreview` both call this,
    /// which is `POST /deploy` with `pull_request_id`. The preview record must already exist, except for Docker Image apps.
    public func deployPreview(
        applicationUUID: String,
        pullRequestID: Int,
        force: Bool = false,
        dockerTag: String? = nil
    ) async throws -> DeployResult {
        guard pullRequestID > 0, !applicationUUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CoolifyError(message: "A preview needs an application and a positive pull request number.")
        }
        let result = try await deploy(
            uuid: applicationUUID, force: force, pullRequestID: pullRequestID, dockerTag: dockerTag)
        // Coolify 4.3 can return HTTP 200 with a per-resource error and no queued deployment.
        guard
            result.deployments.contains(where: {
                $0.resourceUUID == applicationUUID && !($0.deploymentUUID ?? "").isEmpty
            })
        else {
            throw CoolifyError(
                message: result.deployments.first(where: { $0.resourceUUID == applicationUUID })?.message
                    ?? result.message ?? "Coolify did not queue the preview deployment.")
        }
        return result
    }

    public func startPreview(
        applicationUUID: String,
        pullRequestID: Int,
        force: Bool = false,
        dockerTag: String? = nil
    ) async throws -> DeployResult {
        try await deployPreview(
            applicationUUID: applicationUUID,
            pullRequestID: pullRequestID,
            force: force,
            dockerTag: dockerTag
        )
    }

    public func restartPreview(
        applicationUUID: String,
        pullRequestID: Int,
        force: Bool = false,
        dockerTag: String? = nil
    ) async throws -> DeployResult {
        try await deployPreview(
            applicationUUID: applicationUUID,
            pullRequestID: pullRequestID,
            force: force,
            dockerTag: dockerTag
        )
    }

    public func deletePreview(applicationUUID: String, pullRequestID: Int) async throws -> QueuedAction {
        try await delete("\(applicationPath(applicationUUID))/previews/\(pullRequestID)")
    }

    public func previewLogs(
        applicationUUID: String,
        pullRequestID: Int,
        window: LogWindow = .lines(100),
        showTimestamps: Bool = false
    ) async throws -> String {
        try await logs(
            "\(applicationPath(applicationUUID))/previews/\(pullRequestID)/logs",
            window: window,
            showTimestamps: showTimestamps
        )
    }
}

private struct RollbackRequest: Encodable { let commit: String }

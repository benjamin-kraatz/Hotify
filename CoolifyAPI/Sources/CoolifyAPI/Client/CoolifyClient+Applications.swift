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
        try await deploy(uuid: applicationUUID, force: force, pullRequestID: pullRequestID, dockerTag: dockerTag)
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

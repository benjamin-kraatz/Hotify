import Foundation

extension CoolifyClient {
    public func databases() async throws -> [Database] {
        try await getList("databases")
    }

    public func database(_ uuid: String) async throws -> Database {
        try await get("databases/\(CoolifyURL.encodePathComponent(uuid))")
    }

    public func startDatabase(_ uuid: String) async throws -> QueuedAction {
        try await post("databases/\(CoolifyURL.encodePathComponent(uuid))/start")
    }

    public func stopDatabase(_ uuid: String, dockerCleanup: Bool = true) async throws -> QueuedAction {
        try await post(
            "databases/\(CoolifyURL.encodePathComponent(uuid))/stop",
            query: [URLQueryItem(name: "docker_cleanup", value: Self.flag(dockerCleanup))]
        )
    }

    public func restartDatabase(_ uuid: String) async throws -> QueuedAction {
        try await post("databases/\(CoolifyURL.encodePathComponent(uuid))/restart")
    }

    public func databaseLogs(
        _ uuid: String,
        window: LogWindow = .lines(100),
        showTimestamps: Bool = false
    ) async throws -> String {
        try await logs(
            "databases/\(CoolifyURL.encodePathComponent(uuid))/logs",
            window: window,
            showTimestamps: showTimestamps
        )
    }
}

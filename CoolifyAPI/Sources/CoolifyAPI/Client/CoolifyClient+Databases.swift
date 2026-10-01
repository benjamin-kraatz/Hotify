import Foundation

extension CoolifyClient {
    public func databases() async throws -> [Database] {
        try await getList("databases")
    }

    public func database(_ uuid: String) async throws -> Database {
        try await get("databases/\(CoolifyURL.encodePathComponent(uuid))")
    }

    /// Changes a database's settings. Turning public access on or off starts or stops its proxy at once.
    ///
    /// Coolify answers 400 when another database on the server already has the public port.
    public func updateDatabase(_ uuid: String, _ update: DatabaseUpdate) async throws {
        let _: QueuedAction = try await patch("databases/\(CoolifyURL.encodePathComponent(uuid))", body: update)
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

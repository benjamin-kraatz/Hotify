import Foundation

extension CoolifyClient {
    public func services() async throws -> [Service] {
        try await getList("services")
    }

    public func service(_ uuid: String) async throws -> Service {
        try await get("services/\(CoolifyURL.encodePathComponent(uuid))")
    }

    public func startService(_ uuid: String) async throws -> QueuedAction {
        try await post("services/\(CoolifyURL.encodePathComponent(uuid))/start")
    }

    public func stopService(_ uuid: String, dockerCleanup: Bool = true) async throws -> QueuedAction {
        try await post(
            "services/\(CoolifyURL.encodePathComponent(uuid))/stop",
            query: [URLQueryItem(name: "docker_cleanup", value: Self.flag(dockerCleanup))]
        )
    }

    public func restartService(_ uuid: String, latest: Bool = false) async throws -> QueuedAction {
        try await post(
            "services/\(CoolifyURL.encodePathComponent(uuid))/restart",
            query: [URLQueryItem(name: "latest", value: Self.flag(latest))]
        )
    }

    public func serviceLogs(
        _ uuid: String,
        window: LogWindow = .lines(100),
        showTimestamps: Bool = false
    ) async throws -> String {
        try await logs(
            "services/\(CoolifyURL.encodePathComponent(uuid))/logs",
            window: window,
            showTimestamps: showTimestamps
        )
    }
}

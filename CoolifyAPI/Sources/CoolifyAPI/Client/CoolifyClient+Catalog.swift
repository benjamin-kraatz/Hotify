import Foundation

extension CoolifyClient {
    public func version() async throws -> String {
        try await text("version")
    }

    /// Health does not require a token. Coolify returns the plain text `OK`.
    public func health() async throws -> String {
        try await text("health")
    }

    /// The team bound to this token.
    public func currentTeam() async throws -> Team {
        try await get("team")
    }

    public func teams() async throws -> [Team] {
        try await getList("teams")
    }

    public func projects() async throws -> [Project] {
        try await getList("projects")
    }

    public func project(_ uuid: String) async throws -> Project {
        try await get("projects/\(CoolifyURL.encodePathComponent(uuid))")
    }

    public func servers() async throws -> [Server] {
        try await getList("servers")
    }

    public func server(_ uuid: String) async throws -> Server {
        try await get("servers/\(CoolifyURL.encodePathComponent(uuid))")
    }

    public func resources(onServer uuid: String) async throws -> [ServerResource] {
        try await getList("servers/\(CoolifyURL.encodePathComponent(uuid))/resources")
    }

    /// Team-wide inventory. The OpenAPI spec types this body as a placeholder string. The live payload is the resource list.
    public func resources() async throws -> [InventoryResource] {
        try await getList("resources")
    }
}

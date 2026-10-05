import Foundation

/// The application, database, or service a move, clone, or migrate request acts on.
public enum PlacementOwner: Sendable, Hashable {
    case application(String)
    case database(String)
    case service(String)

    func path(_ action: String) -> String {
        let root: String
        switch self {
        case .application(let uuid):
            root = "applications/\(CoolifyURL.encodePathComponent(uuid))"
        case .database(let uuid):
            root = "databases/\(CoolifyURL.encodePathComponent(uuid))"
        case .service(let uuid):
            root = "services/\(CoolifyURL.encodePathComponent(uuid))"
        }
        return "\(root)/\(action)"
    }
}

extension CoolifyClient {
    /// Moves the resource into another environment.
    ///
    /// Organizational only: running containers stay up. The resource picks up the new environment's shared
    /// variables on the next deploy.
    public func moveResource(_ owner: PlacementOwner, to environmentUUID: String) async throws -> PlacementResult {
        try await post(owner.path("move"), body: MoveResourceRequest(environmentUUID: environmentUUID))
    }

    /// Clones the resource onto a destination. A nil name keeps the current one, and `clone_volumes` stays out of
    /// the body unless it is true, which is how Coolify's default of false is left alone.
    public func cloneResource(_ owner: PlacementOwner, _ request: CloneResourceRequest) async throws
        -> PlacementResult
    {
        try await post(owner.path("clone"), body: request)
    }

    /// Migrates the resource to another server.
    ///
    /// Coolify stops it, and can copy persistent volumes when it manages both servers. A nil `migrate_volumes`
    /// keeps Coolify's default, which is to transfer them. The resource has to be deployed again afterward.
    /// An empty success body is a completed migrate that sent no message.
    public func migrateResource(
        _ owner: PlacementOwner, _ request: MigrateResourceRequest
    ) async throws -> PlacementResult {
        let action = try await acknowledge(
            "POST", path: owner.path("migrate"), body: try CoolifyJSON.encoder().encode(request))
        return PlacementResult(message: action.message)
    }
}

import Foundation

/// Whether a compose container is one of the service's applications or one of its databases.
public enum ServiceContainerRole: Sendable {
    case application
    case database

    var pathGroup: String {
        switch self {
        case .application: "applications"
        case .database: "databases"
        }
    }
}

extension CoolifyClient {
    /// Application containers for a service. The nested service payload often omits each uuid; this list has it.
    public func serviceApplications(_ serviceUUID: String) async throws -> [ServiceApplication] {
        try await getList(serviceContainerListPath(serviceUUID, role: .application))
    }

    /// Database containers for a service. The nested service payload often omits each uuid; this list has it.
    public func serviceDatabases(_ serviceUUID: String) async throws -> [ServiceApplication] {
        try await getList(serviceContainerListPath(serviceUUID, role: .database))
    }

    /// Starts one compose container. `uuid` is that container's uuid, never its numeric id.
    public func startServiceContainer(
        _ serviceUUID: String,
        role: ServiceContainerRole,
        uuid: String
    ) async throws -> QueuedAction {
        try await acknowledge(
            "POST", path: serviceContainerActionPath(serviceUUID, role: role, uuid: uuid, action: "start"))
    }

    /// Stops one compose container. `uuid` is that container's uuid, never its numeric id.
    public func stopServiceContainer(
        _ serviceUUID: String,
        role: ServiceContainerRole,
        uuid: String
    ) async throws -> QueuedAction {
        try await acknowledge(
            "POST", path: serviceContainerActionPath(serviceUUID, role: role, uuid: uuid, action: "stop"))
    }

    /// Restarts one compose container. `uuid` is that container's uuid, never its numeric id.
    public func restartServiceContainer(
        _ serviceUUID: String,
        role: ServiceContainerRole,
        uuid: String
    ) async throws -> QueuedAction {
        try await acknowledge(
            "POST", path: serviceContainerActionPath(serviceUUID, role: role, uuid: uuid, action: "restart"))
    }

    /// Changes one application container. Fields left nil stay out of the body, so Coolify keeps them.
    ///
    /// `forceDomainOverride` sends the `force_domain_override` query. Coolify answers 409 with
    /// `CoolifyError.conflicts` when another resource has a domain, and saves nothing then. An unexpected body key
    /// is 422, including `force_domain_override` itself, which this endpoint only reads from the query.
    public func updateServiceApplication(
        _ serviceUUID: String,
        uuid: String,
        _ update: ServiceContainerApplicationUpdate,
        forceDomainOverride: Bool = false
    ) async throws {
        let query =
            forceDomainOverride
            ? [URLQueryItem(name: "force_domain_override", value: "true")]
            : []
        _ = try await acknowledge(
            "PATCH",
            path: serviceContainerItemPath(serviceUUID, role: .application, uuid: uuid),
            query: query,
            body: try CoolifyJSON.encoder().encode(update)
        )
    }

    /// Changes one database container. Fields left nil stay out of the body, so Coolify keeps them.
    ///
    /// An unexpected body key is 422. Coolify also answers 422 when `isPublic` is true without `publicPort`.
    public func updateServiceDatabase(
        _ serviceUUID: String,
        uuid: String,
        _ update: ServiceContainerDatabaseUpdate
    ) async throws {
        _ = try await acknowledge(
            "PATCH",
            path: serviceContainerItemPath(serviceUUID, role: .database, uuid: uuid),
            body: try CoolifyJSON.encoder().encode(update)
        )
    }

    private func serviceContainerListPath(_ serviceUUID: String, role: ServiceContainerRole) -> String {
        "services/\(CoolifyURL.encodePathComponent(serviceUUID))/\(role.pathGroup)"
    }

    private func serviceContainerItemPath(
        _ serviceUUID: String,
        role: ServiceContainerRole,
        uuid: String
    ) -> String {
        let service = CoolifyURL.encodePathComponent(serviceUUID)
        let container = CoolifyURL.encodePathComponent(uuid)
        return "services/\(service)/\(role.pathGroup)/\(container)"
    }

    private func serviceContainerActionPath(
        _ serviceUUID: String,
        role: ServiceContainerRole,
        uuid: String,
        action: String
    ) -> String {
        serviceContainerItemPath(serviceUUID, role: role, uuid: uuid) + "/\(action)"
    }
}

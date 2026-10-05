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

    private func serviceContainerListPath(_ serviceUUID: String, role: ServiceContainerRole) -> String {
        "services/\(CoolifyURL.encodePathComponent(serviceUUID))/\(role.pathGroup)"
    }

    private func serviceContainerActionPath(
        _ serviceUUID: String,
        role: ServiceContainerRole,
        uuid: String,
        action: String
    ) -> String {
        let service = CoolifyURL.encodePathComponent(serviceUUID)
        let container = CoolifyURL.encodePathComponent(uuid)
        return "services/\(service)/\(role.pathGroup)/\(container)/\(action)"
    }
}

import Foundation

/// What Coolify should remove with an application, database, or service.
///
/// Volumes, Docker cleanup, and connected networks stay off unless a caller turns them on. Coolify's own defaults
/// would delete all four, so every flag is sent as the word `true` or `false`.
public struct RemovalOptions: Sendable {
    public var configurations: Bool
    public var volumes: Bool
    public var dockerCleanup: Bool
    public var connectedNetworks: Bool

    public init(
        configurations: Bool = true,
        volumes: Bool = false,
        dockerCleanup: Bool = false,
        connectedNetworks: Bool = false
    ) {
        self.configurations = configurations
        self.volumes = volumes
        self.dockerCleanup = dockerCleanup
        self.connectedNetworks = connectedNetworks
    }

    /// Coolify reads these words. Other endpoints use `1` and `0`, which this one does not.
    fileprivate var queryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "delete_configurations", value: Self.word(configurations)),
            URLQueryItem(name: "delete_volumes", value: Self.word(volumes)),
            URLQueryItem(name: "docker_cleanup", value: Self.word(dockerCleanup)),
            URLQueryItem(name: "delete_connected_networks", value: Self.word(connectedNetworks)),
        ]
    }

    private static func word(_ value: Bool) -> String {
        value ? "true" : "false"
    }
}

/// The kind of resource a confirmed delete removes.
public enum RemovalKind: Sendable {
    case application
    case database
    case service

    fileprivate var collection: String {
        switch self {
        case .application: "applications"
        case .database: "databases"
        case .service: "services"
        }
    }
}

extension CoolifyClient {
    /// Deletes an application. Every flag is sent, so a volume Coolify would remove by default stays.
    public func deleteApplication(
        _ uuid: String, options: RemovalOptions = RemovalOptions()
    ) async throws -> QueuedAction {
        try await deleteResource(uuid, kind: .application, options: options)
    }

    /// Deletes a database. Every flag is sent, so a volume Coolify would remove by default stays.
    public func deleteDatabase(
        _ uuid: String, options: RemovalOptions = RemovalOptions()
    ) async throws -> QueuedAction {
        try await deleteResource(uuid, kind: .database, options: options)
    }

    /// Deletes an application, database, or service, and sends every removal flag.
    ///
    /// `deleteService` stays the way provisioning discards a half-created service. That call always removes volumes,
    /// configuration, and networks. This one sends the caller's flags instead.
    public func deleteResource(
        _ uuid: String,
        kind: RemovalKind,
        options: RemovalOptions = RemovalOptions()
    ) async throws -> QueuedAction {
        try await acknowledge(
            "DELETE",
            path: "\(kind.collection)/\(CoolifyURL.encodePathComponent(uuid))",
            query: options.queryItems
        )
    }

    /// Deletes a project. The request has no query flags.
    public func deleteProject(_ uuid: String) async throws -> QueuedAction {
        try await acknowledge("DELETE", path: "projects/\(CoolifyURL.encodePathComponent(uuid))")
    }

    /// Deletes an environment by name or uuid. Coolify answers 400 when the environment still has resources.
    public func deleteEnvironment(_ environment: String, inProject uuid: String) async throws -> QueuedAction {
        let project = CoolifyURL.encodePathComponent(uuid)
        let name = CoolifyURL.encodePathComponent(environment)
        return try await acknowledge("DELETE", path: "projects/\(project)/environments/\(name)")
    }
}

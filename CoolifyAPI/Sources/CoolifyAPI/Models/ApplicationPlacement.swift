import Foundation

/// Where a new application goes, and the fields every source can set. Encoded flat on the create body.
///
/// Coolify 4.3 answers 422 for a key it does not expect, so optional fields stay out when `nil`. The spec lists
/// `environment_name` and `environment_uuid` as required, but Coolify takes either one, so only the uuid goes.
public struct ApplicationPlacement: Encodable, Sendable, Hashable {
    public var projectUUID: String
    public var serverUUID: String
    public var environmentUUID: String
    /// Required when the server has more than one destination.
    public var destinationUUID: String?
    public var name: String?
    public var description: String?
    /// Comma-separated ports the application listens on, such as `3000`.
    public var portsExposes: String?
    /// Starts a deployment once Coolify has created the application.
    public var instantDeploy: Bool

    enum CodingKeys: String, CodingKey {
        case projectUUID = "projectUuid"
        case serverUUID = "serverUuid"
        case environmentUUID = "environmentUuid"
        case destinationUUID = "destinationUuid"
        case name
        case description
        case portsExposes
        case instantDeploy
    }

    public init(
        projectUUID: String,
        serverUUID: String,
        environmentUUID: String,
        destinationUUID: String? = nil,
        name: String? = nil,
        description: String? = nil,
        portsExposes: String? = nil,
        instantDeploy: Bool = true
    ) {
        self.projectUUID = projectUUID
        self.serverUUID = serverUUID
        self.environmentUUID = environmentUUID
        self.destinationUUID = destinationUUID
        self.name = name
        self.description = description
        self.portsExposes = portsExposes
        self.instantDeploy = instantDeploy
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(projectUUID, forKey: .projectUUID)
        try container.encode(serverUUID, forKey: .serverUUID)
        try container.encode(environmentUUID, forKey: .environmentUUID)
        try container.encodeIfPresent(destinationUUID, forKey: .destinationUUID)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(portsExposes, forKey: .portsExposes)
        try container.encode(instantDeploy, forKey: .instantDeploy)
    }
}

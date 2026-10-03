import Foundation

/// The body that creates a database.
///
/// Coolify 4.3 answers 422 for any key it does not expect, so optional fields stay out of the JSON when `nil`. The spec
/// lists both `environment_name` and `environment_uuid` as required, but Coolify takes either one, so only the uuid goes.
public struct DatabaseDraft: Encodable, Sendable, Hashable {
    /// Picks the endpoint. Not part of the body.
    public var engine: DatabaseEngine
    public var name: String?
    public var description: String?
    /// An image with its tag, such as `postgres:17-alpine`. `nil` takes Coolify's default for the engine.
    public var image: String?
    public var serverUUID: String
    public var projectUUID: String
    public var environmentUUID: String
    /// Required when the server has more than one destination.
    public var destinationUUID: String?
    public var isPublic: Bool?
    public var publicPort: Int?
    /// Starts the database once Coolify created it.
    public var instantDeploy: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case image
        case serverUUID = "serverUuid"
        case projectUUID = "projectUuid"
        case environmentUUID = "environmentUuid"
        case destinationUUID = "destinationUuid"
        case isPublic
        case publicPort
        case instantDeploy
    }

    public init(
        engine: DatabaseEngine,
        name: String? = nil,
        description: String? = nil,
        image: String? = nil,
        serverUUID: String,
        projectUUID: String,
        environmentUUID: String,
        destinationUUID: String? = nil,
        isPublic: Bool? = nil,
        publicPort: Int? = nil,
        instantDeploy: Bool = true
    ) {
        self.engine = engine
        self.name = name
        self.description = description
        self.image = image
        self.serverUUID = serverUUID
        self.projectUUID = projectUUID
        self.environmentUUID = environmentUUID
        self.destinationUUID = destinationUUID
        self.isPublic = isPublic
        self.publicPort = publicPort
        self.instantDeploy = instantDeploy
    }
}

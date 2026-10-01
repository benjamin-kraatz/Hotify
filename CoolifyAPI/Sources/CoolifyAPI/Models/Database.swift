import Foundation

/// A standalone database. Containers that belong to a service stay on `Service`.
public struct Database: Decodable, Sendable, Identifiable, Hashable, HasResourceStatus {
    public var uuid: String
    public var name: String?
    public var status: String?
    /// The engine, such as `standalone-postgresql`. Coolify appends this attribute; the OpenAPI schema omits it.
    public var databaseType: String?
    public var environmentID: Int?
    public var description: String?
    /// Whether the proxy lets the internet reach the database on `publicPort`.
    public var isPublic: Bool?
    public var publicPort: Int?
    /// Only `isEnabled` and the timings apply to a database.
    public var healthCheck: HealthCheck?

    public var id: String { uuid }

    enum CodingKeys: String, CodingKey {
        case uuid
        case name
        case status
        case databaseType
        case environmentID = "environmentId"
        case description
        case isPublic
        case publicPort
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try container.decode(String.self, forKey: .uuid)
        name = container.flexString(.name)
        status = container.flexString(.status)
        databaseType = container.flexString(.databaseType)
        environmentID = container.flexInt(.environmentID)
        description = container.flexString(.description)
        isPublic = container.flexBool(.isPublic)
        publicPort = container.flexInt(.publicPort)
        healthCheck = try? HealthCheck(from: decoder)
    }
}

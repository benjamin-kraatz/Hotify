import Foundation

/// One container inside a service. This is not an `Application`: the id is numeric and there is no uuid.
public struct ServiceApplication: Decodable, Sendable, Identifiable, Hashable, HasResourceStatus {
    public var id: Int
    public var name: String
    public var humanName: String?
    public var status: String?
    public var fqdn: String?
    public var image: String?
    public var excludeFromStatus: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case humanName
        case status
        case fqdn
        case image
        case excludeFromStatus
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.flexInt(.id) ?? 0
        name = container.flexString(.name) ?? ""
        humanName = container.flexString(.humanName)
        status = container.flexString(.status)
        fqdn = container.flexString(.fqdn)
        image = container.flexString(.image)
        excludeFromStatus = container.flexBool(.excludeFromStatus)
    }
}

/// A Docker Compose service and the containers Coolify nests under it.
public struct Service: Decodable, Sendable, Identifiable, Hashable, HasResourceStatus {
    public var uuid: String
    public var name: String
    public var description: String?
    public var status: String?
    public var serviceType: String?
    public var applications: [ServiceApplication]?
    /// The service's database containers. Only `GET /services/{uuid}` includes them. They share the container shape.
    public var databases: [ServiceApplication]?
    public var environmentID: Int?
    /// Tag names when the payload includes them. Absent means none were loaded.
    public var tags: [String] = []

    public var id: String { uuid }

    enum CodingKeys: String, CodingKey {
        case uuid
        case name
        case description
        case status
        case serviceType
        case applications
        case databases
        case environmentID = "environmentId"
        case tags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try container.decode(String.self, forKey: .uuid)
        name = container.flexString(.name) ?? ""
        description = container.flexString(.description)
        status = container.flexString(.status)
        serviceType = container.flexString(.serviceType)
        applications = try container.decodeIfPresent([ServiceApplication].self, forKey: .applications)
        databases = try? container.decodeIfPresent([ServiceApplication].self, forKey: .databases)
        environmentID = container.flexInt(.environmentID)
        tags = container.flexTagNames(.tags)
    }
}

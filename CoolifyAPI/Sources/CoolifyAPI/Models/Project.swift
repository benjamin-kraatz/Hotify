import Foundation

/// A Coolify project. `GET /projects/{uuid}` includes its environments; the list endpoint may not.
public struct Project: Decodable, Sendable, Hashable {
    public var id: Int?
    public var uuid: String
    public var name: String?
    public var description: String?
    public var environments: [Environment]?
    /// Only on `GET /projects/{uuid}`. The list endpoint selects four columns, and the OpenAPI schema omits this one.
    public var createdAt: String?

    public var createdAtDate: Date? { createdAt.flatMap(CoolifyTimestamp.parse) }

    public init(
        id: Int? = nil, uuid: String, name: String? = nil, description: String? = nil,
        environments: [Environment]? = nil, createdAt: String? = nil
    ) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.description = description
        self.environments = environments
        self.createdAt = createdAt
    }
}

import Foundation

/// One S3-compatible bucket Coolify can copy backups into.
public struct S3Storage: Decodable, Sendable, Hashable, Identifiable {
    public var uuid: String
    public var name: String
    public var description: String?
    public var endpoint: String
    public var bucket: String
    public var region: String
    public var isUsable: Bool

    public var id: String { uuid }

    public init(
        uuid: String,
        name: String,
        description: String? = nil,
        endpoint: String,
        bucket: String,
        region: String,
        isUsable: Bool
    ) {
        self.uuid = uuid
        self.name = name
        self.description = description
        self.endpoint = endpoint
        self.bucket = bucket
        self.region = region
        self.isUsable = isUsable
    }

    enum CodingKeys: String, CodingKey {
        case uuid
        case name
        case description
        case endpoint
        case bucket
        case region
        case isUsable
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = container.flexString(.uuid) ?? ""
        name = container.flexString(.name) ?? ""
        description = container.flexString(.description)
        endpoint = container.flexString(.endpoint) ?? ""
        bucket = container.flexString(.bucket) ?? ""
        region = container.flexString(.region) ?? ""
        isUsable = container.flexBool(.isUsable) ?? false
    }
}

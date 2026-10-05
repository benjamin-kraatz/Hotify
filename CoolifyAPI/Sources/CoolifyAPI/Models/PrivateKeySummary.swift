import Foundation

/// A deploy key Coolify already has, named for a picker. The private key material is not decoded.
public struct PrivateKeySummary: Decodable, Sendable, Hashable, Identifiable, CustomStringConvertible {
    public var uuid: String
    public var name: String

    public var id: String { uuid }

    enum CodingKeys: String, CodingKey {
        case uuid
        case name
    }

    public init(uuid: String, name: String) {
        self.uuid = uuid
        self.name = name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let uuid = container.flexString(.uuid), !uuid.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .uuid, in: container, debugDescription: "Private key uuid is missing.")
        }
        self.uuid = uuid
        name = container.flexString(.name) ?? ""
    }

    public var description: String { "PrivateKeySummary(uuid: \(uuid))" }
}

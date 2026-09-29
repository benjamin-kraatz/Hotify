import Foundation

/// One row from `GET /resources`. The spec types that body as a placeholder string; the live payload is this list.
public struct InventoryResource: Decodable, Sendable, Identifiable, Hashable, HasResourceStatus {
    public var uuid: String
    public var name: String?
    public var type: String?
    public var status: String?

    public var id: String { uuid }

    enum CodingKeys: String, CodingKey {
        case uuid
        case name
        case type
        case status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let uuid = container.flexString(.uuid), !uuid.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .uuid,
                in: container,
                debugDescription: "Resource is missing a uuid."
            )
        }
        self.uuid = uuid
        name = container.flexString(.name)
        type = container.flexString(.type)
        status = container.flexString(.status)
    }
}

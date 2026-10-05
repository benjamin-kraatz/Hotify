import Foundation

/// A GitHub App installed on a Coolify instance. `id` is what the repository routes take. `uuid` is what creating
/// an application takes. Secrets Coolify stores on the app are not decoded.
public struct GitHubApp: Decodable, Sendable, Hashable, Identifiable, CustomStringConvertible {
    public var id: Int
    public var uuid: String
    public var name: String
    public var organization: String?

    enum CodingKeys: String, CodingKey {
        case id
        case uuid
        case name
        case organization
    }

    public init(id: Int, uuid: String, name: String, organization: String? = nil) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.organization = organization
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = container.flexInt(.id) else {
            throw DecodingError.dataCorruptedError(
                forKey: .id, in: container, debugDescription: "GitHub app id is missing.")
        }
        guard let uuid = container.flexString(.uuid), !uuid.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .uuid, in: container, debugDescription: "GitHub app uuid is missing.")
        }
        self.id = id
        self.uuid = uuid
        name = container.flexString(.name) ?? ""
        organization = container.flexString(.organization)
    }

    public var description: String { "GitHubApp(uuid: \(uuid))" }
}

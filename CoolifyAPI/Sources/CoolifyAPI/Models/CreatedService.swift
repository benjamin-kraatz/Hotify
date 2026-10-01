import Foundation

/// What Coolify returns after it creates or changes a service: its uuid and the domains its containers answer on.
public struct CreatedService: Decodable, Sendable, Hashable {
    public var uuid: String
    public var domains: [String]

    enum CodingKeys: String, CodingKey {
        case uuid
        case domains
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = container.flexString(.uuid) ?? ""
        domains = (try? container.decodeIfPresent([String].self, forKey: .domains)) ?? []
    }
}

import Foundation

/// A domain that another resource already answers on. Coolify returns these with HTTP 409.
public struct DomainConflict: Decodable, Sendable, Hashable {
    public var domain: String
    public var resourceName: String?
    public var resourceType: String?
    public var message: String?

    enum CodingKeys: String, CodingKey {
        case domain
        case resourceName
        case resourceType
        case message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        domain = container.flexString(.domain) ?? ""
        resourceName = container.flexString(.resourceName)
        resourceType = container.flexString(.resourceType)
        message = container.flexString(.message)
    }

    public init(domain: String, resourceName: String? = nil, resourceType: String? = nil, message: String? = nil) {
        self.domain = domain
        self.resourceName = resourceName
        self.resourceType = resourceType
        self.message = message
    }
}

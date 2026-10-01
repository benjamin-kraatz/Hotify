import Foundation

/// The body that changes a service. Fields left `nil` are not sent, so Coolify keeps them.
public struct ServiceUpdate: Encodable, Sendable, Hashable {
    public var name: String?
    public var description: String?
    public var urls: [ServiceDomain]?
    public var forceDomainOverride: Bool?

    public init(
        name: String? = nil,
        description: String? = nil,
        urls: [ServiceDomain]? = nil,
        forceDomainOverride: Bool? = nil
    ) {
        self.name = name
        self.description = description
        self.urls = urls
        self.forceDomainOverride = forceDomainOverride
    }
}

import Foundation

/// The body that changes a service. Fields left `nil` are not sent, so Coolify keeps them.
public struct ServiceUpdate: Encodable, Sendable, Hashable {
    public var name: String?
    public var description: String?
    /// The whole compose file as written, replacing the stored one. Sent base64-encoded, which is the only form
    /// Coolify takes. Coolify parses it again, keeping the generated passwords and the containers it still names, and
    /// leaves the running containers alone until the service restarts.
    public var dockerComposeRaw: String?
    public var urls: [ServiceDomain]?
    public var forceDomainOverride: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case dockerComposeRaw
        case urls
        case forceDomainOverride
    }

    public init(
        name: String? = nil,
        description: String? = nil,
        dockerComposeRaw: String? = nil,
        urls: [ServiceDomain]? = nil,
        forceDomainOverride: Bool? = nil
    ) {
        self.name = name
        self.description = description
        self.dockerComposeRaw = dockerComposeRaw
        self.urls = urls
        self.forceDomainOverride = forceDomainOverride
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(dockerComposeRaw.map(Base64Text.encode), forKey: .dockerComposeRaw)
        try container.encodeIfPresent(urls, forKey: .urls)
        try container.encodeIfPresent(forceDomainOverride, forKey: .forceDomainOverride)
    }
}

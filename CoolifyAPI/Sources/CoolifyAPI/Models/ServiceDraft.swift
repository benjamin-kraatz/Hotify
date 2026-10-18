import Foundation

/// The body that creates a service, either one-click from a template or from a compose file someone wrote.
///
/// Coolify 4.3 answers 422 for any key it does not expect, so optional fields stay out of the JSON when `nil`.
public struct ServiceDraft: Encodable, Sendable, Hashable {
    /// The template's slug. `nil` for a service made from `dockerComposeRaw`, since Coolify refuses both at once.
    public var type: String?
    /// The compose file as written. Sent base64-encoded, which is the only form Coolify takes.
    public var dockerComposeRaw: String?
    public var name: String?
    public var description: String?
    public var serverUUID: String
    public var projectUUID: String
    public var environmentUUID: String
    /// Required when the server has more than one destination.
    public var destinationUUID: String?
    public var instantDeploy: Bool
    public var urls: [ServiceDomain]?
    public var forceDomainOverride: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case dockerComposeRaw
        case name
        case description
        case serverUUID = "serverUuid"
        case projectUUID = "projectUuid"
        case environmentUUID = "environmentUuid"
        case destinationUUID = "destinationUuid"
        case instantDeploy
        case urls
        case forceDomainOverride
    }

    /// A one-click service from the template `type`.
    public init(
        type: String,
        name: String? = nil,
        description: String? = nil,
        serverUUID: String,
        projectUUID: String,
        environmentUUID: String,
        destinationUUID: String? = nil,
        instantDeploy: Bool = false,
        urls: [ServiceDomain]? = nil,
        forceDomainOverride: Bool? = nil
    ) {
        self.type = type
        self.name = name
        self.description = description
        self.serverUUID = serverUUID
        self.projectUUID = projectUUID
        self.environmentUUID = environmentUUID
        self.destinationUUID = destinationUUID
        self.instantDeploy = instantDeploy
        self.urls = urls
        self.forceDomainOverride = forceDomainOverride
    }

    /// A service from a compose file, sent exactly as written. Coolify names it `service-` and a random suffix when
    /// `name` is `nil`.
    public init(
        compose: String,
        name: String? = nil,
        description: String? = nil,
        serverUUID: String,
        projectUUID: String,
        environmentUUID: String,
        destinationUUID: String? = nil,
        instantDeploy: Bool = false,
        urls: [ServiceDomain]? = nil,
        forceDomainOverride: Bool? = nil
    ) {
        type = nil
        dockerComposeRaw = compose
        self.name = name
        self.description = description
        self.serverUUID = serverUUID
        self.projectUUID = projectUUID
        self.environmentUUID = environmentUUID
        self.destinationUUID = destinationUUID
        self.instantDeploy = instantDeploy
        self.urls = urls
        self.forceDomainOverride = forceDomainOverride
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(dockerComposeRaw.map(Base64Text.encode), forKey: .dockerComposeRaw)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(serverUUID, forKey: .serverUUID)
        try container.encode(projectUUID, forKey: .projectUUID)
        try container.encode(environmentUUID, forKey: .environmentUUID)
        try container.encodeIfPresent(destinationUUID, forKey: .destinationUUID)
        try container.encode(instantDeploy, forKey: .instantDeploy)
        try container.encodeIfPresent(urls, forKey: .urls)
        try container.encodeIfPresent(forceDomainOverride, forKey: .forceDomainOverride)
    }
}

/// The domains of one container in a service. `url` is comma-separated, and empty removes the domain.
public struct ServiceDomain: Encodable, Sendable, Hashable {
    /// The container's name in the compose file, which is `ServiceApplication.name`.
    public var name: String
    public var url: String

    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }
}

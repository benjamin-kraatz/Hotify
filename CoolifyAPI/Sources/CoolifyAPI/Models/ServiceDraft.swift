import Foundation

/// The body that creates a one-click service from a template.
///
/// Coolify 4.3 answers 422 for any key it does not expect, so optional fields stay out of the JSON when `nil`.
public struct ServiceDraft: Encodable, Sendable, Hashable {
    /// The template's slug.
    public var type: String
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

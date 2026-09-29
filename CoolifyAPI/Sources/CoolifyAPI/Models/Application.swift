import Foundation

/// Application flags. `is_force_https_enabled` becomes `isForceHttpsEnabled` after snake_case conversion,
/// which does not match a property spelled `isForceHTTPSEnabled`.
public struct ApplicationSettings: Decodable, Sendable, Hashable {
    public var isPreviewDeploymentsEnabled: Bool?
    public var isForceHTTPSEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case isPreviewDeploymentsEnabled
        case isForceHTTPSEnabled = "isForceHttpsEnabled"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isPreviewDeploymentsEnabled = container.flexBool(.isPreviewDeploymentsEnabled)
        isForceHTTPSEnabled = container.flexBool(.isForceHTTPSEnabled)
    }
}

/// A standalone Coolify application. Service containers use `ServiceApplication` instead.
public struct Application: Decodable, Sendable, Hashable, HasResourceStatus {
    public var id: Int?
    public var uuid: String
    public var name: String
    public var description: String?
    public var status: String?
    public var fqdn: String?
    public var gitRepository: String?
    public var gitBranch: String?
    public var buildPack: String?
    public var createdAt: String?
    public var settings: ApplicationSettings?
    /// The environment the application lives in. Match it against `Project.environments` to find its project.
    public var environmentID: Int?

    public var createdAtDate: Date? { createdAt.flatMap(CoolifyTimestamp.parse) }

    enum CodingKeys: String, CodingKey {
        case id
        case uuid
        case name
        case description
        case status
        case fqdn
        case gitRepository
        case gitBranch
        case buildPack
        case createdAt
        case settings
        case environmentID = "environmentId"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.flexInt(.id)
        uuid = try container.decode(String.self, forKey: .uuid)
        name = container.flexString(.name) ?? ""
        description = container.flexString(.description)
        status = container.flexString(.status)
        fqdn = container.flexString(.fqdn)
        gitRepository = container.flexString(.gitRepository)
        gitBranch = container.flexString(.gitBranch)
        buildPack = container.flexString(.buildPack)
        createdAt = container.flexString(.createdAt)
        settings = try container.decodeIfPresent(ApplicationSettings.self, forKey: .settings)
        environmentID = container.flexInt(.environmentID)
    }
}

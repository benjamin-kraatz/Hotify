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

    public var createdAtDate: Date? { createdAt.flatMap(CoolifyTimestamp.parse) }
}

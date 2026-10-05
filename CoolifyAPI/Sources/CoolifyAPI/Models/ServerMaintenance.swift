import Foundation

/// How often Coolify prunes Docker on a server, and what a run is allowed to delete.
///
/// Nil fields stay out of a PATCH body, so Coolify keeps them. Coolify 4.3 answers 422 to a key it does not expect.
public struct DockerCleanupSettings: Codable, Sendable, Hashable {
    /// A cron expression or a human frequency, such as `daily`.
    public var dockerCleanupFrequency: String?
    /// How full the disk must be, from 1 to 99, before a scheduled cleanup runs.
    public var dockerCleanupThreshold: Int?
    public var forceDockerCleanup: Bool?
    public var deleteUnusedVolumes: Bool?
    public var deleteUnusedNetworks: Bool?
    public var disableApplicationImageRetention: Bool?

    enum CodingKeys: String, CodingKey {
        case dockerCleanupFrequency
        case dockerCleanupThreshold
        case forceDockerCleanup
        case deleteUnusedVolumes
        case deleteUnusedNetworks
        case disableApplicationImageRetention
    }

    public init(
        dockerCleanupFrequency: String? = nil,
        dockerCleanupThreshold: Int? = nil,
        forceDockerCleanup: Bool? = nil,
        deleteUnusedVolumes: Bool? = nil,
        deleteUnusedNetworks: Bool? = nil,
        disableApplicationImageRetention: Bool? = nil
    ) {
        self.dockerCleanupFrequency = dockerCleanupFrequency
        self.dockerCleanupThreshold = dockerCleanupThreshold
        self.forceDockerCleanup = forceDockerCleanup
        self.deleteUnusedVolumes = deleteUnusedVolumes
        self.deleteUnusedNetworks = deleteUnusedNetworks
        self.disableApplicationImageRetention = disableApplicationImageRetention
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dockerCleanupFrequency = container.flexString(.dockerCleanupFrequency)
        dockerCleanupThreshold = container.flexInt(.dockerCleanupThreshold)
        forceDockerCleanup = container.flexBool(.forceDockerCleanup)
        deleteUnusedVolumes = container.flexBool(.deleteUnusedVolumes)
        deleteUnusedNetworks = container.flexBool(.deleteUnusedNetworks)
        disableApplicationImageRetention = container.flexBool(.disableApplicationImageRetention)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let frequency = dockerCleanupFrequency?.trimmingCharacters(in: .whitespacesAndNewlines), !frequency.isEmpty {
            try container.encode(frequency, forKey: .dockerCleanupFrequency)
        }
        try container.encodeIfPresent(dockerCleanupThreshold, forKey: .dockerCleanupThreshold)
        try container.encodeIfPresent(forceDockerCleanup, forKey: .forceDockerCleanup)
        try container.encodeIfPresent(deleteUnusedVolumes, forKey: .deleteUnusedVolumes)
        try container.encodeIfPresent(deleteUnusedNetworks, forKey: .deleteUnusedNetworks)
        try container.encodeIfPresent(disableApplicationImageRetention, forKey: .disableApplicationImageRetention)
    }
}

/// One Docker cleanup run on a server.
public struct DockerCleanupExecution: Decodable, Sendable, Hashable, Identifiable {
    public var uuid: String
    public var status: String
    public var message: String?
    public var createdAt: String?
    public var finishedAt: String?
    public var id: String { uuid }
    public var createdAtDate: Date? { createdAt.flatMap(CoolifyTimestamp.parse) }
    public var finishedAtDate: Date? { finishedAt.flatMap(CoolifyTimestamp.parse) }

    enum CodingKeys: String, CodingKey {
        case uuid
        case status
        case message
        case createdAt
        case finishedAt
    }

    public init(
        uuid: String,
        status: String,
        message: String? = nil,
        createdAt: String? = nil,
        finishedAt: String? = nil
    ) {
        self.uuid = uuid
        self.status = status
        self.message = message
        self.createdAt = createdAt
        self.finishedAt = finishedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = container.flexString(.uuid) ?? ""
        status = container.flexString(.status) ?? "unknown"
        message = container.flexString(.message)
        createdAt = container.flexString(.createdAt)
        finishedAt = container.flexString(.finishedAt)
    }
}

/// The proxy Coolify runs on a server.
///
/// The raw compose `configuration` is not decoded. It needs `read:sensitive` and is a credential-adjacent file.
public struct ServerProxy: Decodable, Sendable, Hashable {
    public var status: String?
    public var proxyType: String?
    public var redirectEnabled: Bool?
    public var redirectUrl: String?

    enum CodingKeys: String, CodingKey {
        case status
        case proxyType
        case redirectEnabled
        case redirectUrl
    }

    public init(
        status: String? = nil,
        proxyType: String? = nil,
        redirectEnabled: Bool? = nil,
        redirectUrl: String? = nil
    ) {
        self.status = status
        self.proxyType = proxyType
        self.redirectEnabled = redirectEnabled
        self.redirectUrl = redirectUrl
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = container.flexString(.status)
        proxyType = container.flexString(.proxyType)
        redirectEnabled = container.flexBool(.redirectEnabled)
        redirectUrl = container.flexString(.redirectUrl)
    }
}

/// The domains that use one address on a server.
public struct ServerDomainGroup: Decodable, Sendable, Hashable, Identifiable {
    public var ip: String
    public var domains: [String]
    public var id: String { ip + "\u{1f}" + domains.joined(separator: "\u{1f}") }

    enum CodingKeys: String, CodingKey {
        case ip
        case domains
    }

    public init(ip: String, domains: [String]) {
        self.ip = ip
        self.domains = domains
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ip = container.flexString(.ip) ?? ""
        domains = (try? container.decode([String].self, forKey: .domains)) ?? []
    }
}

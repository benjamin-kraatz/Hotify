import Foundation

/// The body for `POST /servers`. A nil field stays out of the JSON.
public struct ServerDraft: Encodable, Sendable, Hashable {
    public var name: String?
    public var description: String?
    public var ip: String?
    public var port: Int?
    public var user: String?
    public var privateKeyUUID: String?
    public var isBuildServer: Bool?
    public var instantValidate: Bool?
    /// `traefik`, `caddy`, or `none`.
    public var proxyType: String?

    public init(
        name: String? = nil,
        description: String? = nil,
        ip: String? = nil,
        port: Int? = nil,
        user: String? = nil,
        privateKeyUUID: String? = nil,
        isBuildServer: Bool? = nil,
        instantValidate: Bool? = nil,
        proxyType: String? = nil
    ) {
        self.name = name
        self.description = description
        self.ip = ip
        self.port = port
        self.user = user
        self.privateKeyUUID = privateKeyUUID
        self.isBuildServer = isBuildServer
        self.instantValidate = instantValidate
        self.proxyType = proxyType
    }

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case ip
        case port
        case user
        case privateKeyUUID
        case isBuildServer
        case instantValidate
        case proxyType
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(ip, forKey: .ip)
        try container.encodeIfPresent(port, forKey: .port)
        try container.encodeIfPresent(user, forKey: .user)
        try container.encodeIfPresent(privateKeyUUID, forKey: .privateKeyUUID)
        try container.encodeIfPresent(isBuildServer, forKey: .isBuildServer)
        try container.encodeIfPresent(instantValidate, forKey: .instantValidate)
        try container.encodeIfPresent(proxyType, forKey: .proxyType)
    }
}

/// The body for `PATCH /servers/{uuid}`.
///
/// Nil fields stay out of the JSON. Coolify 4.3 answers 422 to a key it does not expect, including a capacity
/// field that was left unset.
public struct ServerUpdate: Encodable, Sendable, Hashable {
    public var name: String?
    public var description: String?
    public var ip: String?
    public var port: Int?
    public var user: String?
    public var privateKeyUUID: String?
    public var isBuildServer: Bool?
    public var instantValidate: Bool?
    /// `traefik`, `caddy`, or `none`.
    public var proxyType: String?
    public var concurrentBuilds: Int?
    public var dynamicTimeout: Int?
    public var deploymentQueueLimit: Int?
    public var serverDiskUsageNotificationThreshold: Int?
    public var serverDiskUsageCheckFrequency: String?
    public var connectionTimeout: Int?

    public init(
        name: String? = nil,
        description: String? = nil,
        ip: String? = nil,
        port: Int? = nil,
        user: String? = nil,
        privateKeyUUID: String? = nil,
        isBuildServer: Bool? = nil,
        instantValidate: Bool? = nil,
        proxyType: String? = nil,
        concurrentBuilds: Int? = nil,
        dynamicTimeout: Int? = nil,
        deploymentQueueLimit: Int? = nil,
        serverDiskUsageNotificationThreshold: Int? = nil,
        serverDiskUsageCheckFrequency: String? = nil,
        connectionTimeout: Int? = nil
    ) {
        self.name = name
        self.description = description
        self.ip = ip
        self.port = port
        self.user = user
        self.privateKeyUUID = privateKeyUUID
        self.isBuildServer = isBuildServer
        self.instantValidate = instantValidate
        self.proxyType = proxyType
        self.concurrentBuilds = concurrentBuilds
        self.dynamicTimeout = dynamicTimeout
        self.deploymentQueueLimit = deploymentQueueLimit
        self.serverDiskUsageNotificationThreshold = serverDiskUsageNotificationThreshold
        self.serverDiskUsageCheckFrequency = serverDiskUsageCheckFrequency
        self.connectionTimeout = connectionTimeout
    }

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case ip
        case port
        case user
        case privateKeyUUID
        case isBuildServer
        case instantValidate
        case proxyType
        case concurrentBuilds
        case dynamicTimeout
        case deploymentQueueLimit
        case serverDiskUsageNotificationThreshold
        case serverDiskUsageCheckFrequency
        case connectionTimeout
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(ip, forKey: .ip)
        try container.encodeIfPresent(port, forKey: .port)
        try container.encodeIfPresent(user, forKey: .user)
        try container.encodeIfPresent(privateKeyUUID, forKey: .privateKeyUUID)
        try container.encodeIfPresent(isBuildServer, forKey: .isBuildServer)
        try container.encodeIfPresent(instantValidate, forKey: .instantValidate)
        try container.encodeIfPresent(proxyType, forKey: .proxyType)
        try container.encodeIfPresent(concurrentBuilds, forKey: .concurrentBuilds)
        try container.encodeIfPresent(dynamicTimeout, forKey: .dynamicTimeout)
        try container.encodeIfPresent(deploymentQueueLimit, forKey: .deploymentQueueLimit)
        try container.encodeIfPresent(
            serverDiskUsageNotificationThreshold, forKey: .serverDiskUsageNotificationThreshold)
        try container.encodeIfPresent(serverDiskUsageCheckFrequency, forKey: .serverDiskUsageCheckFrequency)
        try container.encodeIfPresent(connectionTimeout, forKey: .connectionTimeout)
    }
}

/// The body for `POST /security/keys`. `private_key` is required. Name and description stay out when nil.
///
/// The key is sent once. This value's description never includes it.
public struct PrivateKeyDraft: Encodable, Sendable, Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    public var name: String?
    public var descriptionText: String?
    public var privateKey: String

    public init(name: String? = nil, description: String? = nil, privateKey: String) {
        self.name = name
        descriptionText = description
        self.privateKey = privateKey
    }

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case privateKey
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(descriptionText, forKey: .description)
        try container.encode(privateKey, forKey: .privateKey)
    }

    public var description: String { "PrivateKeyDraft(name: \(name ?? ""))" }
    public var debugDescription: String { description }
}

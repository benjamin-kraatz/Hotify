import Foundation

/// Flags Coolify returns on a server. Several of them arrive as `0`/`1` rather than JSON booleans.
public struct ServerSettings: Decodable, Sendable, Hashable {
    public var isReachable: Bool?
    public var isUsable: Bool?
    public var isSentinelEnabled: Bool?
    /// A build server only builds images. Coolify refuses to put resources on it.
    public var isBuildServer: Bool?
    /// How many builds Coolify runs on this server at once.
    public var concurrentBuilds: Int?
    /// Seconds a deployment may run.
    public var dynamicTimeout: Int?
    /// How many deployments may wait.
    public var deploymentQueueLimit: Int?
    /// Seconds to wait for an SSH connection.
    public var connectionTimeout: Int?
    /// Percent full before Coolify warns. Some responses nest the server's disk fields here.
    public var serverDiskUsageNotificationThreshold: Int?
    /// Cron expression for the disk check, when the response nests it under settings.
    public var serverDiskUsageCheckFrequency: String?

    enum CodingKeys: String, CodingKey {
        case isReachable
        case isUsable
        case isSentinelEnabled
        case isBuildServer
        case concurrentBuilds
        case dynamicTimeout
        case deploymentQueueLimit
        case connectionTimeout
        case serverDiskUsageNotificationThreshold
        case serverDiskUsageCheckFrequency
    }

    public init(
        isReachable: Bool? = nil,
        isUsable: Bool? = nil,
        isSentinelEnabled: Bool? = nil,
        isBuildServer: Bool? = nil,
        concurrentBuilds: Int? = nil,
        dynamicTimeout: Int? = nil,
        deploymentQueueLimit: Int? = nil,
        connectionTimeout: Int? = nil,
        serverDiskUsageNotificationThreshold: Int? = nil,
        serverDiskUsageCheckFrequency: String? = nil
    ) {
        self.isReachable = isReachable
        self.isUsable = isUsable
        self.isSentinelEnabled = isSentinelEnabled
        self.isBuildServer = isBuildServer
        self.concurrentBuilds = concurrentBuilds
        self.dynamicTimeout = dynamicTimeout
        self.deploymentQueueLimit = deploymentQueueLimit
        self.connectionTimeout = connectionTimeout
        self.serverDiskUsageNotificationThreshold = serverDiskUsageNotificationThreshold
        self.serverDiskUsageCheckFrequency = serverDiskUsageCheckFrequency
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isReachable = container.flexBool(.isReachable)
        isUsable = container.flexBool(.isUsable)
        isSentinelEnabled = container.flexBool(.isSentinelEnabled)
        isBuildServer = container.flexBool(.isBuildServer)
        concurrentBuilds = container.flexInt(.concurrentBuilds)
        dynamicTimeout = container.flexInt(.dynamicTimeout)
        deploymentQueueLimit = container.flexInt(.deploymentQueueLimit)
        connectionTimeout = container.flexInt(.connectionTimeout)
        serverDiskUsageNotificationThreshold = container.flexInt(.serverDiskUsageNotificationThreshold)
        serverDiskUsageCheckFrequency = container.flexString(.serverDiskUsageCheckFrequency)
    }
}

/// A machine Coolify deploys to. Reachability is also copied onto the server itself, outside `settings`.
public struct Server: Decodable, Sendable, Hashable {
    public var id: Int?
    public var uuid: String
    public var name: String
    public var description: String?
    public var ip: String?
    public var user: String?
    public var port: Int?
    /// Uuid of the key Coolify uses to connect. The key material is not decoded.
    public var privateKeyUUID: String?
    public var isCoolifyHost: Bool?
    public var isReachable: Bool?
    public var isUsable: Bool?
    /// Percent full before Coolify warns.
    public var serverDiskUsageNotificationThreshold: Int?
    /// Cron expression for the disk check.
    public var serverDiskUsageCheckFrequency: String?
    public var settings: ServerSettings?

    enum CodingKeys: String, CodingKey {
        case id
        case uuid
        case name
        case description
        case ip
        case user
        case port
        case privateKeyUuid
        case privateKey
        case isCoolifyHost
        case isReachable
        case isUsable
        case serverDiskUsageNotificationThreshold
        case serverDiskUsageCheckFrequency
        case settings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.flexInt(.id)
        uuid = container.flexString(.uuid) ?? ""
        name = container.flexString(.name) ?? ""
        description = container.flexString(.description)
        ip = container.flexString(.ip)
        user = container.flexString(.user)
        port = container.flexInt(.port)
        // The list and the detail sometimes nest the key as an object that also carries the key material.
        // Only the uuid is kept. A string in that field is ignored, so the material is never stored.
        privateKeyUUID = container.flexString(.privateKeyUuid)
        if privateKeyUUID?.isEmpty != false {
            privateKeyUUID = (try? container.decodeIfPresent(ServerKeyReference.self, forKey: .privateKey))?.uuid
        }
        if privateKeyUUID?.isEmpty == true {
            privateKeyUUID = nil
        }
        isCoolifyHost = container.flexBool(.isCoolifyHost)
        isReachable = container.flexBool(.isReachable)
        isUsable = container.flexBool(.isUsable)
        serverDiskUsageNotificationThreshold = container.flexInt(.serverDiskUsageNotificationThreshold)
        serverDiskUsageCheckFrequency = container.flexString(.serverDiskUsageCheckFrequency)
        settings = try container.decodeIfPresent(ServerSettings.self, forKey: .settings)
    }

    public init(uuid: String, name: String, ip: String? = nil, isReachable: Bool? = nil, isUsable: Bool? = nil) {
        self.uuid = uuid
        self.name = name
        self.ip = ip
        self.isReachable = isReachable
        self.isUsable = isUsable
    }
}

/// The uuid of a server's key. `private_key` on the object is the material, and it is not decoded.
private struct ServerKeyReference: Decodable {
    var uuid: String?

    enum CodingKeys: String, CodingKey {
        case uuid
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = container.flexString(.uuid)
        uuid = value?.isEmpty == true ? nil : value
    }
}

/// A resource row from `GET /servers/{uuid}/resources`.
public struct ServerResource: Decodable, Sendable, Hashable, HasResourceStatus {
    public var id: Int?
    public var uuid: String
    public var name: String?
    public var type: String?
    public var status: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case uuid
        case name
        case type
        case status
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.flexInt(.id)
        uuid = container.flexString(.uuid) ?? ""
        name = container.flexString(.name)
        type = container.flexString(.type)
        status = container.flexString(.status)
        createdAt = container.flexString(.createdAt)
        updatedAt = container.flexString(.updatedAt)
    }
}

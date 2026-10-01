import Foundation

/// Flags Coolify returns on a server. Several of them arrive as `0`/`1` rather than JSON booleans.
public struct ServerSettings: Decodable, Sendable, Hashable {
    public var isReachable: Bool?
    public var isUsable: Bool?
    public var isSentinelEnabled: Bool?
    /// A build server only builds images. Coolify refuses to put resources on it.
    public var isBuildServer: Bool?

    enum CodingKeys: String, CodingKey {
        case isReachable
        case isUsable
        case isSentinelEnabled
        case isBuildServer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isReachable = container.flexBool(.isReachable)
        isUsable = container.flexBool(.isUsable)
        isSentinelEnabled = container.flexBool(.isSentinelEnabled)
        isBuildServer = container.flexBool(.isBuildServer)
    }
}

/// A machine Coolify deploys to. Reachability is also copied onto the server itself, outside `settings`.
public struct Server: Decodable, Sendable, Hashable {
    public var id: Int?
    public var uuid: String
    public var name: String
    public var ip: String?
    public var port: Int?
    public var isCoolifyHost: Bool?
    public var isReachable: Bool?
    public var isUsable: Bool?
    public var settings: ServerSettings?

    enum CodingKeys: String, CodingKey {
        case id
        case uuid
        case name
        case ip
        case port
        case isCoolifyHost
        case isReachable
        case isUsable
        case settings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.flexInt(.id)
        uuid = container.flexString(.uuid) ?? ""
        name = container.flexString(.name) ?? ""
        ip = container.flexString(.ip)
        port = container.flexInt(.port)
        isCoolifyHost = container.flexBool(.isCoolifyHost)
        isReachable = container.flexBool(.isReachable)
        isUsable = container.flexBool(.isUsable)
        settings = try container.decodeIfPresent(ServerSettings.self, forKey: .settings)
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

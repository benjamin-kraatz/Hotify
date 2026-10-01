import Foundation

/// A Docker network on a server that resources deploy into. Most servers have exactly one.
public struct Destination: Decodable, Sendable, Hashable, Identifiable {
    public var uuid: String
    public var name: String
    public var network: String?
    public var serverUUID: String?

    public var id: String { uuid }

    enum CodingKeys: String, CodingKey {
        case uuid
        case name
        case network
        case serverUUID = "serverUuid"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = container.flexString(.uuid) ?? ""
        name = container.flexString(.name) ?? ""
        network = container.flexString(.network)
        serverUUID = container.flexString(.serverUUID)
    }

    public init(uuid: String, name: String, network: String? = nil, serverUUID: String? = nil) {
        self.uuid = uuid
        self.name = name
        self.network = network
        self.serverUUID = serverUUID
    }
}

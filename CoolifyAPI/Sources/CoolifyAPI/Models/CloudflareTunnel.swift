import Foundation

/// Whether a server is reached through a Cloudflare Tunnel, and the addresses Coolify has stored.
///
/// `isCloudflareTunnel` may arrive as `0` or `1`. Recording the flag does not install or remove cloudflared.
public struct CloudflareTunnel: Decodable, Sendable, Hashable {
    public var ip: String?
    public var ipPrevious: String?
    public var isCloudflareTunnel: Bool?

    enum CodingKeys: String, CodingKey {
        case ip
        case ipPrevious
        case isCloudflareTunnel
    }

    public init(ip: String? = nil, ipPrevious: String? = nil, isCloudflareTunnel: Bool? = nil) {
        self.ip = ip
        self.ipPrevious = ipPrevious
        self.isCloudflareTunnel = isCloudflareTunnel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ip = container.flexString(.ip)
        ipPrevious = container.flexString(.ipPrevious)
        isCloudflareTunnel = container.flexBool(.isCloudflareTunnel)
    }
}

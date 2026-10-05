import Foundation

/// The body that creates a Docker network destination on a server.
///
/// Coolify 4.3 answers 422 for a key it does not expect, so a nil or blank name or type stays out of the JSON.
/// `network` is required. `type`, when set, is `standalone` or `swarm`.
public struct DestinationDraft: Encodable, Sendable, Hashable {
    public var name: String?
    public var network: String
    /// `standalone` or `swarm`. Nil stays out of the body.
    public var type: String?

    enum CodingKeys: String, CodingKey {
        case name
        case network
        case type
    }

    public init(name: String? = nil, network: String, type: String? = nil) {
        self.name = name
        self.network = network
        self.type = type
    }

    /// Leaves a nil or blank name or type out of the JSON.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let name = Self.present(name) {
            try container.encode(name, forKey: .name)
        }
        try container.encode(network.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .network)
        if let type = Self.present(type) {
            try container.encode(type, forKey: .type)
        }
    }

    /// A blank name or type is left out, the same as nil.
    private static func present(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

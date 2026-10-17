import Foundation

/// One line of `docker ps --format '{{json .}}'` on a server.
public struct DockerContainer: Decodable, Hashable, Sendable, Identifiable {
    public var id: String
    /// The first of Docker's names. Docker lists more only for legacy links.
    public var name: String
    public var image: String?
    public var state: String?
    /// Docker's own words, such as `Up 3 hours (healthy)`.
    public var status: String?
    public var labels: [String: String]

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case names = "Names"
        case image = "Image"
        case state = "State"
        case status = "Status"
        case labels = "Labels"
    }

    public init(
        id: String, name: String, image: String? = nil, state: String? = nil, status: String? = nil,
        labels: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.state = state
        self.status = status
        self.labels = labels
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let names = try container.decodeIfPresent(String.self, forKey: .names) ?? ""
        name = names.split(separator: ",").first.map(String.init) ?? ""
        image = try container.decodeIfPresent(String.self, forKey: .image)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        labels = Self.labels(try container.decodeIfPresent(String.self, forKey: .labels) ?? "")
    }

    /// Docker joins labels as `key=value,key=value` without escaping, and a Traefik rule's value can hold a comma.
    /// A piece that doesn't start with a key belongs to the value before it.
    static func labels(_ joined: String) -> [String: String] {
        var labels: [String: String] = [:]
        var lastKey: String?
        for piece in joined.split(separator: ",", omittingEmptySubsequences: false) {
            if let equals = piece.firstIndex(of: "="), isLabelKey(piece[..<equals]) {
                let key = String(piece[..<equals])
                labels[key] = String(piece[piece.index(after: equals)...])
                lastKey = key
            } else if let lastKey {
                labels[lastKey, default: ""] += "," + piece
            }
        }
        return labels
    }

    private static func isLabelKey(_ key: Substring) -> Bool {
        !key.isEmpty && key.allSatisfy { $0.isLetter || $0.isNumber || "._-/".contains($0) }
    }
}

import Foundation

/// A branch of a GitHub App repository. GitHub sends an object with a name. A bare name is accepted too.
public struct GitHubAppBranch: Decodable, Sendable, Hashable, Identifiable {
    public var name: String

    public var id: String { name }

    public init(name: String) {
        self.name = name
    }

    public init(from decoder: Decoder) throws {
        // An object is the GitHub shape. A bare string is accepted so a shorter payload still lists.
        // The string is tried on a single-value container first: asking for a keyed container from a string
        // fails the whole value on some decoders.
        let single = try decoder.singleValueContainer()
        if let name = try? single.decode(String.self) {
            self.name = name
            return
        }
        name = try single.decode(NamedBranch.self).name
    }
}

private struct NamedBranch: Decodable {
    var name: String

    enum CodingKeys: String, CodingKey {
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.flexString(.name) ?? ""
    }
}

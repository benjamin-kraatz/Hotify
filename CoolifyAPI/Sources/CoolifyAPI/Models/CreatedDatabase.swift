import Foundation

/// What Coolify answers when it creates a database: its uuid, and how to connect to it.
///
/// The connection strings carry the password Coolify generated. Coolify sends them at creation even to a token
/// without `read:sensitive`, which a later read of the database hides. They stay out of `description`.
public struct CreatedDatabase: Decodable, Sendable, Hashable, CustomStringConvertible {
    public var uuid: String
    /// The address other resources on the server's network use.
    public var internalURL: String?
    /// The address from outside, when the database is public.
    public var externalURL: String?

    enum CodingKeys: String, CodingKey {
        case uuid
        // snake_case conversion gives `internalDbUrl`, not the acronym spellings.
        case internalURL = "internalDbUrl"
        case externalURL = "externalDbUrl"
    }

    public init(uuid: String, internalURL: String? = nil, externalURL: String? = nil) {
        self.uuid = uuid
        self.internalURL = internalURL
        self.externalURL = externalURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try container.decode(String.self, forKey: .uuid)
        internalURL = container.flexString(.internalURL)
        externalURL = container.flexString(.externalURL)
    }

    public var description: String { "CreatedDatabase(uuid: \(uuid))" }
}

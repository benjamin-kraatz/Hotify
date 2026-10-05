import Foundation

/// A tag on the current team. Resources share these by name.
public struct Tag: Decodable, Sendable, Hashable, Identifiable {
    public var uuid: String
    public var name: String

    public var id: String { uuid.isEmpty ? name : uuid }

    public init(uuid: String, name: String) {
        self.uuid = uuid
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case uuid
        case name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = container.flexString(.uuid) ?? ""
        name = container.flexString(.name) ?? ""
    }
}

/// What `POST /tags` returned.
///
/// Coolify's create answers with the team tag alone and does not attach it to a resource. A list would mean the
/// response already carried the resource's tags.
public struct TagCreation: Decodable, Sendable, Hashable {
    public var tag: Tag
    /// Tags from the response when it is a list. Empty when Coolify only created the team tag.
    public var resourceTags: [Tag]
    /// False when the body is the team tag, so the caller still has to add it to the resource.
    public var isAttachedToResource: Bool

    public init(from decoder: Decoder) throws {
        if var list = try? decoder.unkeyedContainer() {
            var tags: [Tag] = []
            while !list.isAtEnd {
                tags.append(try list.decode(Tag.self))
            }
            resourceTags = tags
            tag = tags.first ?? Tag(uuid: "", name: "")
            isAttachedToResource = true
            return
        }
        tag = try Tag(from: decoder)
        resourceTags = []
        isAttachedToResource = false
    }
}

extension KeyedDecodingContainer {
    /// Tag names from a field the OpenAPI schema may omit.
    ///
    /// Coolify sends an array of strings or of objects with `name`. A missing field, null, or any other shape is
    /// empty, so the rest of the resource still decodes.
    func flexTagNames(_ key: Key) -> [String] {
        guard contains(key) else { return [] }
        if (try? decodeNil(forKey: key)) == true { return [] }
        if let names = try? decode([String].self, forKey: key) {
            return names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let tags = try? decode([Tag].self, forKey: key) {
            return tags.map(\.name).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        return []
    }
}

import Foundation

/// The application, database, or service whose tags a request reads or changes.
public enum TagOwner: Sendable, Hashable {
    case application(String)
    case database(String)
    case service(String)

    var path: String {
        switch self {
        case .application(let uuid):
            "applications/\(CoolifyURL.encodePathComponent(uuid))/tags"
        case .database(let uuid):
            "databases/\(CoolifyURL.encodePathComponent(uuid))/tags"
        case .service(let uuid):
            "services/\(CoolifyURL.encodePathComponent(uuid))/tags"
        }
    }

    func tagPath(_ tagUUID: String) -> String {
        "\(path)/\(CoolifyURL.encodePathComponent(tagUUID))"
    }
}

extension CoolifyClient {
    /// The current team's tags.
    public func tags() async throws -> [Tag] {
        try await getList("tags")
    }

    /// Creates a team tag. The body is `{ "name" }` and the name needs at least 2 characters.
    ///
    /// Coolify 4.3 answers 422 for any other key, and 409 when the team already has the name. The response is the
    /// team tag. It does not attach the tag to a resource; see `TagCreation.isAttachedToResource`.
    public func createTag(name: String) async throws -> TagCreation {
        try await post("tags", body: TagNameBody(name: try Self.tagName(name)))
    }

    /// Renames a team tag. The body is `{ "name" }`. Coolify 4.3 answers 422 for any other key.
    public func renameTag(_ uuid: String, name: String) async throws -> Tag {
        try await patch("tags/\(CoolifyURL.encodePathComponent(uuid))", body: TagNameBody(name: try Self.tagName(name)))
    }

    public func deleteTag(_ uuid: String) async throws {
        try await acknowledge("DELETE", path: "tags/\(CoolifyURL.encodePathComponent(uuid))")
    }

    /// The tags on one application, database, or service.
    public func resourceTags(for owner: TagOwner) async throws -> [Tag] {
        try await getList(owner.path)
    }

    /// Adds one tag by name. The body is `{ "tag_name" }`, not `tag_names`.
    ///
    /// Coolify 4.3 answers 422 when both keys are sent, or when the body has a key it does not expect. The name
    /// needs at least 2 characters. Coolify creates the team tag if it does not exist yet.
    public func addTag(_ name: String, to owner: TagOwner) async throws -> [Tag] {
        try await post(owner.path, body: TagAssignmentBody(tagName: try Self.tagName(name)))
    }

    public func removeTag(_ tagUUID: String, from owner: TagOwner) async throws {
        try await acknowledge("DELETE", path: owner.tagPath(tagUUID))
    }

    private static func tagName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            throw CoolifyError(statusCode: 422, message: "A tag name needs at least 2 characters.")
        }
        return trimmed
    }
}

/// `POST /tags` and `PATCH /tags/{uuid}`. Coolify 4.3 answers 422 for a key other than `name`.
private struct TagNameBody: Encodable {
    var name: String
}

/// One tag on a resource. `tag_names` stays out. Coolify 4.3 answers 422 when both keys are present.
private struct TagAssignmentBody: Encodable {
    var tagName: String
}

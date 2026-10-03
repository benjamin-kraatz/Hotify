import Foundation

/// One Docker image Coolify kept for an application. For a built application, the tag is the commit it was built from.
/// For a Docker image application, it is the image tag the server pulled.
public struct RollbackImage: Decodable, Sendable, Hashable, Identifiable {
    public var tag: String
    public var createdAt: String?
    public var isCurrent: Bool

    public var id: String { tag }

    public init(tag: String, createdAt: String? = nil, isCurrent: Bool = false) {
        self.tag = tag
        self.createdAt = createdAt
        self.isCurrent = isCurrent
    }

    enum CodingKeys: String, CodingKey { case tag, createdAt, isCurrent }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tag = container.flexString(.tag) ?? ""
        createdAt = container.flexString(.createdAt)
        isCurrent = container.flexBool(.isCurrent) ?? false
    }

    /// Coolify passes Docker's `CreatedAt` through, as in `2026-10-01 12:00:00 +0000 UTC`, not ISO 8601.
    public var createdAtDate: Date? {
        guard let createdAt else { return nil }
        let parts = createdAt.split(separator: " ")
        // The trailing zone name, such as `UTC` or `CEST`, repeats the offset before it, and formatters misread some.
        if parts.count == 4 {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
            if let date = formatter.date(from: parts.prefix(3).joined(separator: " ")) {
                return date
            }
        }
        return CoolifyTimestamp.parse(createdAt)
    }

    /// A full 40-character commit SHA, which a built application's image carries.
    public var isCommit: Bool {
        tag.count == 40 && tag.allSatisfy(\.isHexDigit)
    }

    /// The tag as a person reads it: a commit shortened to 7 characters, any other tag in full.
    public var shortTag: String {
        isCommit ? String(tag.prefix(7)) : tag
    }

    /// Coolify's own images share the application's repository: the build stage as `build` and `<sha>-build`, and
    /// previews as `pr-<id>-<sha>`. None of them is a version to go back to.
    public var isHelper: Bool {
        tag.isEmpty || tag == "<none>" || tag == "build" || tag.hasSuffix("-build") || tag.hasPrefix("pr-")
    }

    /// Whether a deployment of `commit` built this image. Either side may be shortened, so a prefix of 7 or more
    /// characters counts.
    public func matches(commit: String?) -> Bool {
        guard isCommit, let commit = commit?.lowercased(), commit.count >= 7, commit.allSatisfy(\.isHexDigit) else {
            return false
        }
        let tag = tag.lowercased()
        return tag.hasPrefix(commit) || commit.hasPrefix(tag)
    }
}

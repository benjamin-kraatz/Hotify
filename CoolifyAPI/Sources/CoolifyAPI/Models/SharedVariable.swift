import Foundation

/// A variable resources can reference, as `{{team.KEY}}`, `{{project.KEY}}`, `{{environment.KEY}}`, or
/// `{{server.KEY}}`.
///
/// Coolify leaves out `value` when the token lacks the `read:sensitive` ability, and for any variable saved with
/// `isShownOnce`. It stays `nil` then, which is different from an empty value.
public struct SharedVariable: Decodable, Sendable, Hashable, Identifiable {
    /// Coolify addresses a shared variable by this number. Unlike a resource's variable, it has no uuid.
    public var id: Int
    public var key: String
    public var value: String?
    /// Coolify passes a literal value through as written and does not expand `$` references in it.
    public var isLiteral: Bool
    public var isMultiline: Bool
    public var isShownOnce: Bool
    public var comment: String?

    enum CodingKeys: String, CodingKey {
        case id
        case key
        case value
        case isLiteral
        case isMultiline
        case isShownOnce
        case comment
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = container.flexInt(.id) else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "Shared variable is missing an id."
            )
        }
        self.id = id
        key = container.flexString(.key) ?? ""
        value = container.flexString(.value)
        isLiteral = container.flexBool(.isLiteral) ?? false
        isMultiline = container.flexBool(.isMultiline) ?? false
        isShownOnce = container.flexBool(.isShownOnce) ?? false
        comment = container.flexString(.comment)
    }
}

/// The body for creating or updating a shared variable.
///
/// Coolify answers 422 to any field it does not list for shared variables, such as `is_preview`, so this has its own
/// type rather than borrowing `EnvironmentVariableDraft`. Creating a team variable requires `key`. A nil stays out
/// of the body.
public struct SharedVariableDraft: Encodable, Sendable, Hashable {
    public var key: String
    public var value: String
    public var isLiteral: Bool
    public var isMultiline: Bool
    public var isShownOnce: Bool
    /// Left out of the body when `nil`, which keeps the comment Coolify already has.
    public var comment: String?

    public init(
        key: String,
        value: String,
        isLiteral: Bool = false,
        isMultiline: Bool = false,
        isShownOnce: Bool = false,
        comment: String? = nil
    ) {
        self.key = key
        self.value = value
        self.isLiteral = isLiteral
        self.isMultiline = isMultiline
        self.isShownOnce = isShownOnce
        self.comment = comment
    }
}

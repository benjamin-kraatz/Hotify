import Foundation

/// One environment variable on an application, database, or service.
///
/// Coolify leaves out `value` and `realValue` when the token lacks the `read:sensitive` ability, and for any
/// variable saved with `isShownOnce`. Both stay `nil` then, which is different from an empty value.
public struct EnvironmentVariable: Decodable, Sendable, Hashable, Identifiable {
    public var uuid: String
    public var key: String
    public var value: String?
    /// The value with shared variable references such as `{{team.API_URL}}` filled in.
    public var realValue: String?
    /// Applications keep a second set of variables for preview deployments.
    public var isPreview: Bool
    /// Coolify passes a literal value through as written and does not expand `$` references in it.
    public var isLiteral: Bool
    public var isMultiline: Bool
    public var isShownOnce: Bool
    /// `nil` on Coolify versions without separate build and runtime flags.
    public var isRuntime: Bool?
    public var isBuildtime: Bool?
    public var comment: String?
    public var updatedAt: String?

    public var id: String { uuid }
    public var updatedAtDate: Date? { updatedAt.flatMap(CoolifyTimestamp.parse) }

    enum CodingKeys: String, CodingKey {
        case uuid
        case key
        case value
        case realValue
        case isPreview
        case isLiteral
        case isMultiline
        case isShownOnce
        case isRuntime
        case isBuildtime
        case comment
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = container.flexString(.uuid) ?? ""
        // The spec's create response is only `{ "uuid": … }`. 4.3.x returns the whole variable.
        key = container.flexString(.key) ?? ""
        value = container.flexString(.value)
        realValue = container.flexString(.realValue)
        isPreview = container.flexBool(.isPreview) ?? false
        isLiteral = container.flexBool(.isLiteral) ?? false
        isMultiline = container.flexBool(.isMultiline) ?? false
        isShownOnce = container.flexBool(.isShownOnce) ?? false
        isRuntime = container.flexBool(.isRuntime)
        isBuildtime = container.flexBool(.isBuildtime)
        comment = container.flexString(.comment)
        updatedAt = container.flexString(.updatedAt)
    }
}

/// The body for creating or updating an environment variable.
///
/// Coolify 4.3 updates every flag it is sent and resets the flags an application request leaves out, so this
/// always carries all of them. `isPreview` is only sent for applications, the one type that has preview variables.
public struct EnvironmentVariableDraft: Encodable, Sendable, Hashable {
    public var key: String
    public var value: String
    public var isPreview: Bool?
    public var isLiteral: Bool
    public var isMultiline: Bool
    public var isShownOnce: Bool

    public init(
        key: String,
        value: String,
        isPreview: Bool? = nil,
        isLiteral: Bool = false,
        isMultiline: Bool = false,
        isShownOnce: Bool = false
    ) {
        self.key = key
        self.value = value
        self.isPreview = isPreview
        self.isLiteral = isLiteral
        self.isMultiline = isMultiline
        self.isShownOnce = isShownOnce
    }
}

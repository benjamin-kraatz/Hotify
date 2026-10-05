import Foundation

/// One S3-compatible bucket Coolify can copy backups into.
public struct S3Storage: Decodable, Sendable, Hashable, Identifiable {
    public var uuid: String
    public var name: String
    public var description: String?
    public var endpoint: String
    public var bucket: String
    public var region: String
    public var isUsable: Bool

    public var id: String { uuid }

    public init(
        uuid: String,
        name: String,
        description: String? = nil,
        endpoint: String,
        bucket: String,
        region: String,
        isUsable: Bool
    ) {
        self.uuid = uuid
        self.name = name
        self.description = description
        self.endpoint = endpoint
        self.bucket = bucket
        self.region = region
        self.isUsable = isUsable
    }

    enum CodingKeys: String, CodingKey {
        case uuid
        case name
        case description
        case endpoint
        case bucket
        case region
        case isUsable
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = container.flexString(.uuid) ?? ""
        name = container.flexString(.name) ?? ""
        description = container.flexString(.description)
        endpoint = container.flexString(.endpoint) ?? ""
        bucket = container.flexString(.bucket) ?? ""
        region = container.flexString(.region) ?? ""
        isUsable = container.flexBool(.isUsable) ?? false
    }
}

/// Whether Coolify could list the bucket.
public struct S3StorageValidation: Decodable, Sendable, Hashable {
    public var valid: Bool
    public var message: String?

    enum CodingKeys: String, CodingKey { case valid, message }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        valid = container.flexBool(.valid) ?? false
        message = container.flexString(.message)
    }
}

/// The body that creates an S3-compatible backup store.
///
/// Required fields are always encoded. Optional fields stay out of the JSON when `nil`. Coolify stores `isUsable`
/// as false when the request omits it, so send the flag when the store should be usable.
public struct S3StorageDraft: Encodable, Sendable, Hashable {
    public var name: String
    public var description: String?
    public var endpoint: String
    public var bucket: String
    public var region: String
    public var key: String
    /// The secret is a credential. Keep a draft out of logs, previews, and any description.
    public var secret: String
    public var isUsable: Bool?

    public init(
        name: String,
        description: String? = nil,
        endpoint: String,
        bucket: String,
        region: String,
        key: String,
        secret: String,
        isUsable: Bool? = nil
    ) {
        self.name = name
        self.description = description
        self.endpoint = endpoint
        self.bucket = bucket
        self.region = region
        self.key = key
        self.secret = secret
        self.isUsable = isUsable
    }

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case endpoint
        case bucket
        case region
        case key
        case secret
        case isUsable
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(endpoint, forKey: .endpoint)
        try container.encode(bucket, forKey: .bucket)
        try container.encode(region, forKey: .region)
        try container.encode(key, forKey: .key)
        try container.encode(secret, forKey: .secret)
        try container.encodeIfPresent(isUsable, forKey: .isUsable)
    }
}

/// The body that changes an S3-compatible backup store.
///
/// Nil fields stay out of the JSON. A blank key or secret is omitted so Coolify keeps the stored credential. The list
/// response includes neither one.
public struct S3StorageUpdate: Encodable, Sendable, Hashable {
    public var name: String?
    public var description: String?
    public var endpoint: String?
    public var bucket: String?
    public var region: String?
    public var key: String?
    public var secret: String?
    public var isUsable: Bool?

    public init(
        name: String? = nil,
        description: String? = nil,
        endpoint: String? = nil,
        bucket: String? = nil,
        region: String? = nil,
        key: String? = nil,
        secret: String? = nil,
        isUsable: Bool? = nil
    ) {
        self.name = name
        self.description = description
        self.endpoint = endpoint
        self.bucket = bucket
        self.region = region
        self.key = key
        self.secret = secret
        self.isUsable = isUsable
    }

    public var isEmpty: Bool {
        name == nil && description == nil && endpoint == nil && bucket == nil && region == nil && key == nil
            && secret == nil && isUsable == nil
    }

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case endpoint
        case bucket
        case region
        case key
        case secret
        case isUsable
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(endpoint, forKey: .endpoint)
        try container.encodeIfPresent(bucket, forKey: .bucket)
        try container.encodeIfPresent(region, forKey: .region)
        try encodeCredential(key, for: .key, into: &container)
        try encodeCredential(secret, for: .secret, into: &container)
        try container.encodeIfPresent(isUsable, forKey: .isUsable)
    }

    /// A blank credential stays out of the body. Whitespace alone counts as blank.
    private func encodeCredential(
        _ value: String?,
        for key: CodingKeys,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        guard let value else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try container.encode(trimmed, forKey: key)
    }
}

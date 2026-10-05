import Foundation

/// The body that changes one application container of a service. Fields left `nil` stay out of the JSON, so Coolify
/// keeps them.
///
/// Coolify 4.3 answers 422 to any key it does not expect. `url` is comma-separated domains. A taken domain is forced
/// with the `force_domain_override` query, not a body field: Coolify rejects that key here.
public struct ServiceContainerApplicationUpdate: Encodable, Sendable, Hashable {
    /// Comma-separated URLs. Empty removes every domain.
    public var url: String?
    public var humanName: String?
    public var description: String?
    public var image: String?
    public var excludeFromStatus: Bool?

    public init(
        url: String? = nil,
        humanName: String? = nil,
        description: String? = nil,
        image: String? = nil,
        excludeFromStatus: Bool? = nil
    ) {
        self.url = url
        self.humanName = humanName
        self.description = description
        self.image = image
        self.excludeFromStatus = excludeFromStatus
    }

    /// Whether there is anything to send.
    public var isEmpty: Bool {
        url == nil && humanName == nil && description == nil && image == nil && excludeFromStatus == nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(humanName, forKey: .humanName)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encodeIfPresent(excludeFromStatus, forKey: .excludeFromStatus)
    }

    private enum CodingKeys: String, CodingKey {
        case url
        case humanName
        case description
        case image
        case excludeFromStatus
    }
}

/// The body that changes one database container of a service. Fields left `nil` stay out of the JSON, so Coolify
/// keeps them.
///
/// Coolify 4.3 answers 422 to any key it does not expect, and when `isPublic` is true without `publicPort`.
public struct ServiceContainerDatabaseUpdate: Encodable, Sendable, Hashable {
    public var humanName: String?
    public var description: String?
    public var image: String?
    public var excludeFromStatus: Bool?
    /// Opens the database to the internet through the proxy on `publicPort`.
    public var isPublic: Bool?
    public var publicPort: Int?
    public var publicPortTimeout: Int?

    public init(
        humanName: String? = nil,
        description: String? = nil,
        image: String? = nil,
        excludeFromStatus: Bool? = nil,
        isPublic: Bool? = nil,
        publicPort: Int? = nil,
        publicPortTimeout: Int? = nil
    ) {
        self.humanName = humanName
        self.description = description
        self.image = image
        self.excludeFromStatus = excludeFromStatus
        self.isPublic = isPublic
        self.publicPort = publicPort
        self.publicPortTimeout = publicPortTimeout
    }

    /// Whether there is anything to send.
    public var isEmpty: Bool {
        humanName == nil && description == nil && image == nil && excludeFromStatus == nil && isPublic == nil
            && publicPort == nil && publicPortTimeout == nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(humanName, forKey: .humanName)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encodeIfPresent(excludeFromStatus, forKey: .excludeFromStatus)
        try container.encodeIfPresent(isPublic, forKey: .isPublic)
        try container.encodeIfPresent(publicPort, forKey: .publicPort)
        try container.encodeIfPresent(publicPortTimeout, forKey: .publicPortTimeout)
    }

    private enum CodingKeys: String, CodingKey {
        case humanName
        case description
        case image
        case excludeFromStatus
        case isPublic
        case publicPort
        case publicPortTimeout
    }
}

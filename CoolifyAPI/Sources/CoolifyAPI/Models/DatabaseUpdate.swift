import Foundation

/// The body that changes a standalone database. Fields left `nil` stay out of the JSON, so Coolify keeps them.
public struct DatabaseUpdate: Encodable, Sendable, Hashable {
    public var name: String?
    public var description: String?
    /// Opens the database to the internet through the proxy on `publicPort`.
    ///
    /// Coolify starts the proxy only when this turns on with `publicPort` in the same request, so send the port
    /// along with it.
    public var isPublic: Bool?
    public var publicPort: Int?
    /// Only `isEnabled` and the timings are sent. Coolify answers 422 to the other fields on a database.
    public var healthCheck: HealthCheck?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case isPublic
        case publicPort
    }

    public init(
        name: String? = nil,
        description: String? = nil,
        isPublic: Bool? = nil,
        publicPort: Int? = nil,
        healthCheck: HealthCheck? = nil
    ) {
        self.name = name
        self.description = description
        self.isPublic = isPublic
        self.publicPort = publicPort
        self.healthCheck = healthCheck
    }

    public var isEmpty: Bool {
        name == nil && description == nil && isPublic == nil && publicPort == nil && healthCheck == nil
    }

    /// Whether the running database only picks the change up when it restarts. Turning public access on or off
    /// starts or stops the proxy at once, but a new port or health check waits for the restart.
    public var needsRestart: Bool {
        healthCheck != nil || (publicPort != nil && isPublic == nil)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(isPublic, forKey: .isPublic)
        try container.encodeIfPresent(publicPort, forKey: .publicPort)
        if let healthCheck {
            var health = encoder.container(keyedBy: HealthCheck.CodingKeys.self)
            try health.encode(healthCheck.isEnabled, forKey: .isEnabled)
            try healthCheck.encodeTimings(into: &health)
        }
    }
}

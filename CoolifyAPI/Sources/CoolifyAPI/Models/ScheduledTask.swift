import Foundation

/// A command Coolify runs on a schedule for an application or a service.
///
/// `enabled` often arrives as `0` or `1`. Coolify 4.3 hides the numeric `id` on the wire even though the spec lists
/// it, so a missing id reads as `0`. The uuid is what later requests use.
public struct ScheduledTask: Decodable, Sendable, Hashable {
    public var id: Int
    public var uuid: String
    public var enabled: Bool
    public var name: String
    public var command: String
    public var frequency: String
    public var container: String?
    public var timeout: Int
    public var createdAt: String?
    public var updatedAt: String?

    public var createdAtDate: Date? { createdAt.flatMap(CoolifyTimestamp.parse) }
    public var updatedAtDate: Date? { updatedAt.flatMap(CoolifyTimestamp.parse) }

    enum CodingKeys: String, CodingKey {
        case id
        case uuid
        case enabled
        case name
        case command
        case frequency
        case container
        case timeout
        case createdAt
        case updatedAt
    }

    public init(
        id: Int = 0,
        uuid: String,
        enabled: Bool,
        name: String,
        command: String,
        frequency: String,
        container: String? = nil,
        timeout: Int = 300,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.uuid = uuid
        self.enabled = enabled
        self.name = name
        self.command = command
        self.frequency = frequency
        self.container = container
        self.timeout = timeout
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.flexInt(.id) ?? 0
        uuid = container.flexString(.uuid) ?? ""
        enabled = container.flexBool(.enabled) ?? false
        name = container.flexString(.name) ?? ""
        command = container.flexString(.command) ?? ""
        frequency = container.flexString(.frequency) ?? ""
        self.container = container.flexString(.container)
        timeout = container.flexInt(.timeout) ?? 300
        createdAt = container.flexString(.createdAt)
        updatedAt = container.flexString(.updatedAt)
    }
}

/// The body for creating or updating a scheduled task.
///
/// Coolify 4.3 answers 422 to any key it does not expect, so a nil optional stays out of the JSON. On create,
/// Coolify fills in a missing `timeout` with 300 and a missing `enabled` with true.
public struct ScheduledTaskDraft: Encodable, Sendable, Hashable {
    public var name: String
    public var command: String
    public var frequency: String
    public var container: String?
    public var timeout: Int?
    public var enabled: Bool?

    public init(
        name: String,
        command: String,
        frequency: String,
        container: String? = nil,
        timeout: Int? = nil,
        enabled: Bool? = nil
    ) {
        self.name = name
        self.command = command
        self.frequency = frequency
        self.container = container
        self.timeout = timeout
        self.enabled = enabled
    }

    enum CodingKeys: String, CodingKey {
        case name
        case command
        case frequency
        case container
        case timeout
        case enabled
    }

    public func encode(to encoder: Encoder) throws {
        var payload = encoder.container(keyedBy: CodingKeys.self)
        try payload.encode(name, forKey: .name)
        try payload.encode(command, forKey: .command)
        try payload.encode(frequency, forKey: .frequency)
        try payload.encodeIfPresent(container, forKey: .container)
        try payload.encodeIfPresent(timeout, forKey: .timeout)
        try payload.encodeIfPresent(enabled, forKey: .enabled)
    }
}

/// One run of a scheduled task. `status` is `success`, `failed`, or `running`.
public struct ScheduledTaskExecution: Decodable, Sendable, Hashable, Identifiable {
    public var uuid: String
    public var status: String
    public var message: String?
    public var retryCount: Int
    /// Seconds the run took. Coolify sends a number, sometimes as a string.
    public var duration: Double?
    public var startedAt: String?
    public var finishedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    public var id: String { uuid }
    public var startedAtDate: Date? { startedAt.flatMap(CoolifyTimestamp.parse) }
    public var finishedAtDate: Date? { finishedAt.flatMap(CoolifyTimestamp.parse) }
    public var createdAtDate: Date? { createdAt.flatMap(CoolifyTimestamp.parse) }

    enum CodingKeys: String, CodingKey {
        case uuid
        case status
        case message
        case retryCount
        case duration
        case startedAt
        case finishedAt
        case createdAt
        case updatedAt
    }

    public init(
        uuid: String,
        status: String,
        message: String? = nil,
        retryCount: Int = 0,
        duration: Double? = nil,
        startedAt: String? = nil,
        finishedAt: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.uuid = uuid
        self.status = status
        self.message = message
        self.retryCount = retryCount
        self.duration = duration
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = container.flexString(.uuid) ?? ""
        status = container.flexString(.status) ?? "unknown"
        message = container.flexString(.message)
        retryCount = container.flexInt(.retryCount) ?? 0
        duration = container.flexString(.duration).flatMap(Double.init)
        startedAt = container.flexString(.startedAt)
        finishedAt = container.flexString(.finishedAt)
        createdAt = container.flexString(.createdAt)
        updatedAt = container.flexString(.updatedAt)
    }
}

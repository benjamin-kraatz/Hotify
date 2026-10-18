import Foundation

/// One value of a channel setting, as Coolify stores it.
public enum NotificationValue: Sendable, Hashable {
    case bool(Bool)
    case text(String)
    case integer(Int)
    /// Not set. Sending it clears the setting.
    case null
}

/// A team's settings for one alert channel, as Coolify returned them.
///
/// Only keys the channel has are kept, and only the ones Coolify sent. A hidden field that is missing was withheld,
/// since the token cannot read sensitive values. Any other missing field is one this Coolify version does not have.
/// The values can hold webhook addresses and credentials, so the description names keys and never values.
public struct NotificationChannelSettings: Sendable, Hashable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public let channel: NotificationChannel
    public private(set) var values: [String: NotificationValue]

    public init(channel: NotificationChannel, values: [String: NotificationValue]) {
        self.channel = channel
        let known = Set(channel.allFields.map(\.key))
        self.values = values.filter { known.contains($0.key) }
    }

    public func value(_ key: String) -> NotificationValue? {
        values[key]
    }

    public func bool(_ key: String) -> Bool? {
        if case .bool(let value) = values[key] { return value }
        return nil
    }

    /// Text, or a number written out. `nil` when the field is unset or missing.
    public func text(_ key: String) -> String? {
        switch values[key] {
        case .text(let value): value
        case .integer(let value): String(value)
        default: nil
        }
    }

    public func isPresent(_ key: String) -> Bool {
        values[key] != nil
    }

    /// Whether any of the channel's switches is on. For email that is the instance's settings, SMTP, or Resend.
    public var isEnabled: Bool {
        channel.enableKeys.contains { bool($0) == true }
    }

    /// `nil` when this Coolify version has no such event for the channel.
    public func isSubscribed(_ event: NotificationChannelEvent) -> Bool? {
        bool(channel.eventKey(event))
    }

    /// The events this Coolify version offers on the channel.
    public var offeredEvents: [NotificationChannelEvent] {
        NotificationChannelEvent.allCases.filter { isPresent(channel.eventKey($0)) }
    }

    public var subscribedEvents: [NotificationChannelEvent] {
        offeredEvents.filter { isSubscribed($0) == true }
    }

    /// Coolify kept the field back because the token cannot read sensitive values.
    public func isWithheld(_ field: NotificationSettingField) -> Bool {
        field.isHidden && !isPresent(field.key)
    }

    /// Whether this Coolify version has the field. A hidden field counts, since it may only be withheld.
    public func offers(_ field: NotificationSettingField) -> Bool {
        field.isHidden || isPresent(field.key)
    }

    /// Whether Coolify shared the channel's hidden values. It shares all or none of them.
    public var revealsSensitiveValues: Bool {
        channel.allFields.contains { $0.isHidden && isPresent($0.key) }
    }

    public var description: String {
        "NotificationChannelSettings(\(channel.rawValue), keys: \(values.keys.sorted().joined(separator: ", ")))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["channel": channel, "keys": values.keys.sorted()])
    }
}

extension NotificationChannelSettings {
    /// Reads a channel's settings from a response body. Unknown keys, such as `id` and `team_id`, are dropped.
    static func decode(_ channel: NotificationChannel, from data: Data) throws -> Self {
        let payload = try CoolifyJSON.decoder().decode(NotificationSettingsPayload.self, from: data)
        return Self(channel: channel, values: payload.values)
    }
}

/// Every known channel key in one response, read with the flexible helpers.
///
/// `CoolifyJSON.decoder()` converts snake_case keys, so each field is looked up by its camelCase spelling.
struct NotificationSettingsPayload: Decodable {
    var values: [String: NotificationValue] = [:]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SettingKey.self)
        var fieldsByKey: [String: NotificationSettingField] = [:]
        for field in NotificationChannel.allCases.flatMap(\.allFields) {
            fieldsByKey[SettingKey.camelCase(field.key)] = field
        }
        for key in container.allKeys {
            guard let field = fieldsByKey[key.stringValue] else { continue }
            if (try? container.decodeNil(forKey: key)) == true {
                values[field.key] = .null
                continue
            }
            switch field.kind {
            case .toggle:
                // Coolify 4.4 misnames the boolean cast of the Docker cleanup events on Discord, Slack, Telegram, and
                // Pushover, so those come as the raw column value rather than true or false.
                values[field.key] = container.flexBool(key).map(NotificationValue.bool) ?? .null
            case .integer:
                values[field.key] = container.flexInt(key).map(NotificationValue.integer) ?? .null
            default:
                values[field.key] = container.flexString(key).map(NotificationValue.text) ?? .null
            }
        }
    }
}

struct SettingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        nil
    }

    /// Matches `JSONDecoder.KeyDecodingStrategy.convertFromSnakeCase` for the lowercase keys Coolify sends.
    static func camelCase(_ snake: String) -> String {
        let parts = snake.split(separator: "_")
        guard let first = parts.first else { return snake }
        return parts.dropFirst().reduce(String(first)) { $0 + $1.prefix(1).uppercased() + $1.dropFirst() }
    }
}

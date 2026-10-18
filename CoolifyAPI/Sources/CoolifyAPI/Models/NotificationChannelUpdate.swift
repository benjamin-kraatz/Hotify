import Foundation

/// The body that changes some of one channel's settings.
///
/// Only the keys set here are sent, so Coolify keeps every other setting as it is. Keys the channel does not have are
/// dropped, since Coolify fails the whole request with 422 for any of them. A blank credential is dropped too, so a
/// masked or withheld secret is never overwritten by an empty field. Clear one with `clear(_:)`.
///
/// Coolify answers 400 to an empty body. Check `isEmpty` before sending.
public struct NotificationChannelUpdate: Encodable, Sendable, Hashable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let channel: NotificationChannel
    public private(set) var changes: [String: NotificationValue] = [:]

    public init(channel: NotificationChannel) {
        self.channel = channel
    }

    public var isEmpty: Bool { changes.isEmpty }

    /// Sets one key. A key the channel does not have is ignored.
    public mutating func set(_ value: NotificationValue, for key: String) {
        guard let field = channel.field(key) else { return }
        if field.isCredential, case .text(let text) = value {
            setCredential(text, for: key)
            return
        }
        changes[key] = value
    }

    /// Replaces a credential. Blank text, whitespace included, leaves the stored one alone.
    public mutating func setCredential(_ text: String, for key: String) {
        guard channel.field(key) != nil else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            changes[key] = nil
        } else {
            changes[key] = .text(trimmed)
        }
    }

    /// Sends `null`, which removes the stored value.
    public mutating func clear(_ key: String) {
        guard channel.field(key) != nil else { return }
        changes[key] = .null
    }

    public mutating func subscribe(_ event: NotificationChannelEvent, _ isOn: Bool) {
        set(.bool(isOn), for: channel.eventKey(event))
    }

    /// Why Coolify would refuse each changed value, by key.
    public var problems: [String: String] {
        var problems: [String: String] = [:]
        for (key, value) in changes {
            if let problem = channel.field(key)?.problem(with: value) {
                problems[key] = problem
            }
        }
        return problems
    }

    /// The required keys a switch that ends up on would be left without, once this update is applied to `settings`.
    ///
    /// A withheld value the update does not clear counts as set, since only Coolify knows. Coolify's API takes a
    /// channel turned on with nothing to send to, so this mirrors the checks its own settings forms make.
    public func missingKeys(applyingTo settings: NotificationChannelSettings) -> [String] {
        var missing: [String] = []
        for transport in channel.enableKeys where resolvedBool(transport, settings) {
            for key in channel.requiredKeys(for: transport) where !missing.contains(key) {
                if !isFilled(key, settings) { missing.append(key) }
            }
        }
        return missing
    }

    private func resolvedBool(_ key: String, _ settings: NotificationChannelSettings) -> Bool {
        if case .bool(let value) = changes[key] { return value }
        return settings.bool(key) == true
    }

    private func isFilled(_ key: String, _ settings: NotificationChannelSettings) -> Bool {
        switch changes[key] {
        case .text(let text): return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .integer: return true
        case .null: return false
        case .bool, nil: break
        }
        if let field = channel.field(key), settings.isWithheld(field) { return true }
        guard let text = settings.text(key) else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func encode(to encoder: Encoder) throws {
        // The keys are already snake_case, which `convertToSnakeCase` leaves alone.
        var container = encoder.container(keyedBy: SettingKey.self)
        for key in changes.keys.sorted() {
            let codingKey = SettingKey(stringValue: key)
            switch changes[key] {
            case .bool(let value): try container.encode(value, forKey: codingKey)
            case .text(let value): try container.encode(value, forKey: codingKey)
            case .integer(let value): try container.encode(value, forKey: codingKey)
            case .null, nil: try container.encodeNil(forKey: codingKey)
            }
        }
    }

    public var description: String {
        "NotificationChannelUpdate(\(channel.rawValue), keys: \(changes.keys.sorted().joined(separator: ", ")))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["channel": channel, "keys": changes.keys.sorted()])
    }
}

import CoolifyAPI
import Foundation

/// The edits to one channel before Save, kept in memory only.
///
/// Each value starts from what Coolify returned. `update` holds only what differs, so a save leaves every other
/// setting as Coolify has it. A credential starts blank and stays untouched unless something is typed or it is
/// removed on purpose, so a masked or withheld secret is never overwritten with an empty field.
struct AlertChannelDraft: Equatable {
    let settings: NotificationChannelSettings
    var toggles: [String: Bool]
    /// The switches as the form first showed them. A switch Coolify sent unreadable shows off, and stays unsent
    /// unless it is flipped.
    private let initialToggles: [String: Bool]
    var texts: [String: String]
    /// New credentials. Blank keeps the stored one.
    var credentials: [String: String] = [:]
    /// Credentials and withheld values to remove on save.
    var cleared: Set<String> = []

    init(settings: NotificationChannelSettings) {
        self.settings = settings
        var toggles: [String: Bool] = [:]
        var texts: [String: String] = [:]
        for field in settings.channel.allFields where settings.offers(field) {
            switch field.kind {
            case .toggle:
                toggles[field.key] = settings.bool(field.key) ?? false
            default:
                if !field.isCredential {
                    texts[field.key] = settings.text(field.key) ?? ""
                }
            }
        }
        self.toggles = toggles
        initialToggles = toggles
        self.texts = texts
    }

    var channel: NotificationChannel { settings.channel }

    func isOn(_ key: String) -> Bool { toggles[key] ?? false }

    var isEnabled: Bool { channel.enableKeys.contains { isOn($0) } }

    /// The fields this Coolify version has, without the switches.
    var settingFields: [NotificationSettingField] {
        channel.fields.filter { $0.kind != .toggle && settings.offers($0) }
    }

    func field(_ key: String) -> NotificationSettingField? {
        settingFields.first { $0.key == key }
    }

    // MARK: Email transport

    /// How email goes out. Coolify's own form keeps exactly one of these on.
    enum EmailTransport: String, CaseIterable, Identifiable {
        case off
        case instance = "use_instance_email_settings"
        case smtp = "smtp_enabled"
        case resend = "resend_enabled"

        var id: Self { self }

        var title: String {
            switch self {
            case .off: "Off"
            case .instance: "Instance mail settings"
            case .smtp: "SMTP"
            case .resend: "Resend"
            }
        }
    }

    /// The instance's settings win, then SMTP, then Resend, if Coolify somehow has more than one on.
    var emailTransport: EmailTransport {
        get {
            [EmailTransport.instance, .smtp, .resend].first { isOn($0.rawValue) } ?? .off
        }
        set {
            for transport in [EmailTransport.instance, .smtp, .resend] where toggles[transport.rawValue] != nil {
                toggles[transport.rawValue] = transport == newValue
            }
        }
    }

    /// The transports this Coolify version offers.
    var emailTransports: [EmailTransport] {
        EmailTransport.allCases.filter { $0 == .off || toggles[$0.rawValue] != nil }
    }

    /// Turns a non-email channel on or off.
    mutating func setEnabled(_ isOn: Bool) {
        for key in channel.enableKeys where toggles[key] != nil {
            toggles[key] = isOn
        }
    }

    // MARK: Credentials

    /// The stored credential, when Coolify shared it and it is not empty.
    func storedCredential(_ key: String) -> String? {
        guard let text = settings.text(key), !text.isEmpty else { return nil }
        return text
    }

    func isWithheld(_ key: String) -> Bool {
        guard let field = channel.field(key) else { return false }
        return settings.isWithheld(field)
    }

    /// Whether something may be stored that Remove would clear.
    func canRemove(_ key: String) -> Bool {
        storedCredential(key) != nil || isWithheld(key)
    }

    // MARK: The update

    var update: NotificationChannelUpdate {
        var update = NotificationChannelUpdate(channel: channel)
        for (key, value) in toggles where initialToggles[key] != value {
            update.set(.bool(value), for: key)
        }
        for field in channel.allFields where !field.isCredential && field.kind != .toggle {
            guard let text = texts[field.key] else { continue }
            let next = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if settings.isWithheld(field) {
                // Blank keeps whatever Coolify holds, since the field could not start from it.
                if cleared.contains(field.key) {
                    update.clear(field.key)
                } else if !next.isEmpty {
                    update.set(Self.value(next, for: field), for: field.key)
                }
                continue
            }
            guard next != (settings.text(field.key) ?? "") else { continue }
            if next.isEmpty {
                update.clear(field.key)
            } else {
                update.set(Self.value(next, for: field), for: field.key)
            }
        }
        for field in channel.fields where field.isCredential {
            if cleared.contains(field.key) {
                update.clear(field.key)
            } else if let text = credentials[field.key] {
                update.setCredential(text, for: field.key)
            }
        }
        return update
    }

    var hasChanges: Bool { !update.isEmpty }

    /// Why Coolify would refuse a changed value, by key, then what turning the channel on still needs.
    var problems: [String: String] {
        let update = update
        var problems = update.problems
        // Only an edit that turns a switch on or changes what it needs is held back, so a channel Coolify already
        // has half set up can still change its events.
        let required = Set(channel.enableKeys.flatMap { channel.requiredKeys(for: $0) })
        let turnsOn = channel.enableKeys.contains { update.changes[$0] == .bool(true) }
        guard turnsOn || update.changes.keys.contains(where: required.contains) else { return problems }
        for key in update.missingKeys(applyingTo: settings) where problems[key] == nil {
            problems[key] = "Required while \(channel.title) is on."
        }
        return problems
    }

    /// A number field sends a number, unless the text is not one, so the field's own check can say so.
    private static func value(_ text: String, for field: NotificationSettingField) -> NotificationValue {
        if case .integer = field.kind, let number = Int(text) {
            return .integer(number)
        }
        return .text(text)
    }
}

import Foundation

/// One way Coolify sends the team's alerts itself, from the instance, whether or not Hotify runs.
///
/// Each channel is one settings record per team, read with `GET /notifications/<channel>` and changed with
/// `PATCH /notifications/<channel>`. The OpenAPI spec has no request schema for these, so the fields here follow
/// Coolify 4.4's `NotificationsController` rules and the models' `$hidden` lists.
public enum NotificationChannel: String, CaseIterable, Sendable, Hashable, Identifiable {
    case email
    case discord
    case slack
    case telegram
    case pushover
    case webhook

    public var id: Self { self }

    var path: String { "notifications/\(rawValue)" }

    /// The switches that turn the channel on. Email has one per way it can send: the instance's own settings, SMTP,
    /// or Resend.
    public var enableKeys: [String] {
        switch self {
        case .email: ["use_instance_email_settings", "smtp_enabled", "resend_enabled"]
        default: ["\(rawValue)_enabled"]
        }
    }

    /// The channel's own settings, switches first, in the order a form shows them. Event switches are separate.
    public var fields: [NotificationSettingField] {
        switch self {
        case .email:
            [
                .toggle("use_instance_email_settings"),
                .toggle("smtp_enabled"),
                .toggle("resend_enabled"),
                .email("smtp_from_address", hidden: true),
                .text("smtp_from_name", hidden: true, maxLength: 255),
                .text("smtp_recipients", hidden: true, maxLength: 1_000),
                .text("smtp_host", hidden: true, maxLength: 255),
                .integer("smtp_port", 1...65_535),
                .choice("smtp_encryption", ["starttls", "tls", "none"]),
                .text("smtp_username", hidden: true, maxLength: 255),
                .credential("smtp_password"),
                .integer("smtp_timeout", 0...Int.max),
                .hostname("smtp_ehlo_domain"),
                .credential("resend_api_key"),
            ]
        case .discord:
            [
                .toggle("discord_enabled"), .credential("discord_webhook_url", isURL: true),
                .toggle("discord_ping_enabled"),
            ]
        case .slack:
            [.toggle("slack_enabled"), .credential("slack_webhook_url", isURL: true)]
        case .telegram:
            [
                .toggle("telegram_enabled"), .credential("telegram_token"),
                .text("telegram_chat_id", hidden: true, maxLength: 255),
            ]
        case .pushover:
            [.toggle("pushover_enabled"), .credential("pushover_user_key"), .credential("pushover_api_token")]
        case .webhook:
            [.toggle("webhook_enabled"), .credential("webhook_url", isURL: true)]
        }
    }

    /// The key that subscribes this channel to one event, such as `backup_failure_slack_notifications`.
    public func eventKey(_ event: NotificationChannelEvent) -> String {
        "\(event.rawValue)_\(rawValue)_notifications"
    }

    /// The Telegram topic one event posts to. Coolify hides these like the bot token. Other channels have none.
    public func threadKey(_ event: NotificationChannelEvent) -> String? {
        guard self == .telegram else { return nil }
        return "telegram_notifications_\(event.rawValue)_thread_id"
    }

    /// Every key Coolify accepts for this channel. Any other key makes the whole PATCH fail with 422.
    public var allFields: [NotificationSettingField] {
        fields
            + NotificationChannelEvent.allCases.map { .toggle(eventKey($0)) }
            + NotificationChannelEvent.allCases.compactMap { threadKey($0) }.map {
                .text($0, hidden: true, maxLength: 255)
            }
    }

    public func field(_ key: String) -> NotificationSettingField? {
        allFields.first { $0.key == key }
    }

    /// What has to be filled in before Coolify can deliver through `transport`, after Coolify's own settings forms.
    /// The API itself accepts a channel turned on with nothing set, and then every alert fails to send.
    public func requiredKeys(for transport: String) -> [String] {
        switch transport {
        case "smtp_enabled":
            ["smtp_from_address", "smtp_from_name", "smtp_host", "smtp_port", "smtp_encryption"]
        case "resend_enabled":
            ["resend_api_key", "smtp_from_address", "smtp_from_name"]
        case "discord_enabled": ["discord_webhook_url"]
        case "slack_enabled": ["slack_webhook_url"]
        case "telegram_enabled": ["telegram_token", "telegram_chat_id"]
        case "pushover_enabled": ["pushover_user_key", "pushover_api_token"]
        case "webhook_enabled": ["webhook_url"]
        default: []
        }
    }
}

/// Something Coolify can alert about. Every channel offers the same events.
public enum NotificationChannelEvent: String, CaseIterable, Sendable, Hashable, Identifiable {
    case deploymentSuccess = "deployment_success"
    case deploymentFailure = "deployment_failure"
    case statusChange = "status_change"
    case restartLimitReached = "restart_limit_reached"
    case backupSuccess = "backup_success"
    case backupFailure = "backup_failure"
    case scheduledTaskSuccess = "scheduled_task_success"
    case scheduledTaskFailure = "scheduled_task_failure"
    case dockerCleanupSuccess = "docker_cleanup_success"
    case dockerCleanupFailure = "docker_cleanup_failure"
    case serverDiskUsage = "server_disk_usage"
    case serverReachable = "server_reachable"
    case serverUnreachable = "server_unreachable"
    case serverPatch = "server_patch"
    case traefikOutdated = "traefik_outdated"

    public var id: Self { self }
}

/// One setting of a channel: its key on the wire, what it holds, and whether Coolify withholds it.
public struct NotificationSettingField: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case toggle
        case text
        case email
        /// An http or https address. Coolify also refuses loopback, link-local, and private targets.
        case url
        /// A hostname under RFC 1123, such as the SMTP EHLO domain.
        case hostname
        case integer(ClosedRange<Int>)
        case choice([String])
    }

    public let key: String
    public let kind: Kind
    /// Coolify leaves the field out of a response unless the token has `read:sensitive` and its user is a team admin
    /// or owner. A missing hidden field says nothing about whether it is set.
    public let isHidden: Bool
    /// A password, token, key, or webhook address that grants access. Show it masked.
    public let isCredential: Bool
    public let maxLength: Int?

    public var id: String { key }

    public init(key: String, kind: Kind, isHidden: Bool = false, isCredential: Bool = false, maxLength: Int? = nil) {
        self.key = key
        self.kind = kind
        self.isHidden = isHidden
        self.isCredential = isCredential
        self.maxLength = maxLength
    }

    static func toggle(_ key: String) -> Self {
        Self(key: key, kind: .toggle)
    }

    static func text(_ key: String, hidden: Bool = false, maxLength: Int? = nil) -> Self {
        Self(key: key, kind: .text, isHidden: hidden, maxLength: maxLength)
    }

    static func email(_ key: String, hidden: Bool) -> Self {
        Self(key: key, kind: .email, isHidden: hidden)
    }

    static func hostname(_ key: String) -> Self {
        Self(key: key, kind: .hostname, maxLength: 255)
    }

    static func integer(_ key: String, _ range: ClosedRange<Int>) -> Self {
        Self(key: key, kind: .integer(range))
    }

    static func choice(_ key: String, _ options: [String]) -> Self {
        Self(key: key, kind: .choice(options))
    }

    /// Webhook addresses carry their own secret, so Coolify encrypts and hides them like a password.
    static func credential(_ key: String, isURL: Bool = false) -> Self {
        Self(key: key, kind: isURL ? .url : .text, isHidden: true, isCredential: true, maxLength: isURL ? nil : 255)
    }

    /// Why Coolify would refuse `value`, in words for the user, or `nil` when it fits the field's rules.
    ///
    /// The rules follow Coolify 4.4's validator. A webhook address that resolves to a private network still passes
    /// here, since only the instance can resolve it.
    public func problem(with value: NotificationValue) -> String? {
        switch value {
        case .null:
            return nil
        case .bool:
            return kind == .toggle ? nil : "Expected text."
        case .integer(let number):
            guard case .integer(let range) = kind else { return "Expected text." }
            return range.contains(number) ? nil : Self.rangeProblem(range)
        case .text(let text):
            if let maxLength, text.count > maxLength {
                return "Use at most \(maxLength) characters."
            }
            switch kind {
            case .toggle:
                return "Expected on or off."
            case .text:
                return nil
            case .email:
                return Self.isEmail(text) ? nil : "Enter an email address, such as alerts@example.com."
            case .url:
                return Self.isWebURL(text) ? nil : "Enter an http or https address."
            case .hostname:
                return Self.isHostname(text) ? nil : "Enter a hostname, such as mail.example.com."
            case .integer(let range):
                guard let number = Int(text) else { return "Enter a whole number." }
                return range.contains(number) ? nil : Self.rangeProblem(range)
            case .choice(let options):
                return options.contains(text) ? nil : "Choose one of \(options.joined(separator: ", "))."
            }
        }
    }

    private static func rangeProblem(_ range: ClosedRange<Int>) -> String {
        range.upperBound == Int.max
            ? "Enter \(range.lowerBound) or more."
            : "Enter a number from \(range.lowerBound) to \(range.upperBound)."
    }

    private static func isEmail(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !text.contains(where: \.isWhitespace) else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    private static func isWebURL(_ text: String) -> Bool {
        guard !text.contains(where: \.isWhitespace),
            let components = URLComponents(string: text),
            let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = components.host, !host.isEmpty, !host.hasSuffix(".")
        else { return false }
        return true
    }

    /// RFC 1123 labels of letters, digits, and hyphens, as Coolify's `ValidHostname` rule checks them.
    private static func isHostname(_ text: String) -> Bool {
        let host = text.lowercased()
        guard !host.isEmpty, host.count <= 253, !host.hasPrefix("."), !host.hasSuffix(".") else { return false }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        return host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            (1...63).contains(label.count) && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.allSatisfy { allowed.contains($0) }
        }
    }
}

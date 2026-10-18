import CoolifyAPI

/// Names, symbols, and examples for Coolify's alert channels, in the words the forms use.
extension NotificationChannel {
    var title: String {
        switch self {
        case .email: "Email"
        case .discord: "Discord"
        case .slack: "Slack"
        case .telegram: "Telegram"
        case .pushover: "Pushover"
        case .webhook: "Webhook"
        }
    }

    var systemImage: String {
        switch self {
        case .email: "envelope.fill"
        case .discord: "bubble.left.and.bubble.right.fill"
        case .slack: "number"
        case .telegram: "paperplane.fill"
        case .pushover: "bell.and.waves.left.and.right.fill"
        case .webhook: "point.3.connected.trianglepath.dotted"
        }
    }

    /// Where the alerts land, said once under the channel's switch.
    var destination: String {
        switch self {
        case .email: "Coolify emails the recipients you list."
        case .discord: "Coolify posts to a Discord channel through its webhook."
        case .slack: "Coolify posts to a Slack channel through an incoming webhook."
        case .telegram: "Coolify's bot posts to a Telegram chat."
        case .pushover: "Coolify pushes to your devices through Pushover."
        case .webhook: "Coolify sends each alert as JSON to your URL."
        }
    }
}

/// The groups the event switches are listed in.
enum AlertEventGroup: String, CaseIterable, Identifiable {
    case deployments
    case resources
    case backups
    case tasks
    case servers

    var id: Self { self }

    var title: String {
        switch self {
        case .deployments: "Deployments"
        case .resources: "Containers"
        case .backups: "Backups"
        case .tasks: "Scheduled Tasks"
        case .servers: "Servers"
        }
    }

    var events: [NotificationChannelEvent] {
        switch self {
        case .deployments: [.deploymentSuccess, .deploymentFailure]
        case .resources: [.statusChange, .restartLimitReached]
        case .backups: [.backupSuccess, .backupFailure]
        case .tasks: [.scheduledTaskSuccess, .scheduledTaskFailure]
        case .servers:
            [
                .serverUnreachable, .serverReachable, .serverDiskUsage, .serverPatch, .dockerCleanupFailure,
                .dockerCleanupSuccess, .traefikOutdated,
            ]
        }
    }
}

extension NotificationChannelEvent {
    var title: String {
        switch self {
        case .deploymentSuccess: "Deployment finished"
        case .deploymentFailure: "Deployment failed"
        case .statusChange: "Container stopped or changed state"
        case .restartLimitReached: "Container hit its restart limit"
        case .backupSuccess: "Backup finished"
        case .backupFailure: "Backup failed"
        case .scheduledTaskSuccess: "Task finished"
        case .scheduledTaskFailure: "Task failed"
        case .dockerCleanupSuccess: "Docker cleanup finished"
        case .dockerCleanupFailure: "Docker cleanup failed"
        case .serverDiskUsage: "Disk almost full"
        case .serverReachable: "Server reachable again"
        case .serverUnreachable: "Server unreachable"
        case .serverPatch: "Server updates available"
        case .traefikOutdated: "Traefik proxy out of date"
        }
    }

}

/// The label and example a channel setting shows in a form.
struct AlertFieldLabel {
    var title: String
    var prompt: String

    init(_ key: String) {
        switch key {
        case "smtp_from_address": (title, prompt) = ("From address", "alerts@example.com")
        case "smtp_from_name": (title, prompt) = ("From name", "Coolify")
        case "smtp_recipients": (title, prompt) = ("Recipients", "ops@example.com, me@example.com")
        case "smtp_host": (title, prompt) = ("Host", "smtp.example.com")
        case "smtp_port": (title, prompt) = ("Port", "587")
        case "smtp_encryption": (title, prompt) = ("Encryption", "")
        case "smtp_username": (title, prompt) = ("Username", "Optional")
        case "smtp_password": (title, prompt) = ("Password", "Optional")
        case "smtp_timeout": (title, prompt) = ("Timeout in seconds", "Default")
        case "smtp_ehlo_domain": (title, prompt) = ("EHLO domain", "System default")
        case "resend_api_key": (title, prompt) = ("Resend API key", "re_…")
        case "discord_webhook_url": (title, prompt) = ("Webhook URL", "https://discord.com/api/webhooks/…")
        case "discord_ping_enabled": (title, prompt) = ("Mention @here", "")
        case "slack_webhook_url": (title, prompt) = ("Webhook URL", "https://hooks.slack.com/services/…")
        case "telegram_token": (title, prompt) = ("Bot token", "123456:ABC-DEF…")
        case "telegram_chat_id": (title, prompt) = ("Chat ID", "-1001234567890")
        case "pushover_user_key": (title, prompt) = ("User key", "Your Pushover user key")
        case "pushover_api_token": (title, prompt) = ("API token", "The application's token")
        case "webhook_url": (title, prompt) = ("URL", "https://example.com/coolify-alerts")
        default:
            if key.hasPrefix("telegram_notifications_") {
                (title, prompt) = ("Topic ID", "Main chat")
            } else {
                (title, prompt) = (key, "")
            }
        }
    }

    /// The SMTP encryption choices, as Coolify names them.
    static func encryptionTitle(_ value: String) -> String {
        switch value {
        case "starttls": "STARTTLS"
        case "tls": "TLS"
        case "none": "None"
        default: value
        }
    }
}

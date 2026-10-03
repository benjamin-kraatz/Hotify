import Foundation

/// Something Hotify can tell you about, as far as polling Coolify can see it. Restart limits and disk usage only come
/// through Coolify's webhook, so they wait for Hotify Relay.
enum NotificationEvent: String, CaseIterable, Identifiable, Codable {
    case deploymentFailed
    /// A deploy started from this device, including a rollback or a version, finished.
    case deploymentFinished
    /// A deploy started anywhere else, such as a push, finished.
    case deploymentFinishedElsewhere
    case resourceDown
    case backupFailed
    case serverReachability

    var id: Self { self }

    var title: String {
        switch self {
        case .deploymentFailed: "Deployment failed"
        case .deploymentFinished: "Your deploy finished"
        case .deploymentFinishedElsewhere: "Any deploy finished"
        case .resourceDown: "Stopped or unhealthy"
        case .backupFailed: "Backup failed or overdue"
        case .serverReachability: "Server unreachable"
        }
    }

    var detail: String {
        switch self {
        case .deploymentFailed: "A build or a preview failed, wherever it started."
        case .deploymentFinished: "A deploy, rollback, or version you started on this Mac."
        case .deploymentFinishedElsewhere: "Also deploys from a push, Coolify, or another device."
        case .resourceDown: "Something that ran stopped or turned unhealthy, unless you stopped it here."
        case .backupFailed: "A database backup failed, or one is late."
        case .serverReachability: "Coolify lost a server, and when it's back."
        }
    }

    /// Successful deploys from elsewhere are the chattiest, so they stay off until asked for.
    var isOnByDefault: Bool { self != .deploymentFinishedElsewhere }

    /// The plural for a burst summary, as in "7 resources stopped or turned unhealthy".
    func burst(_ count: Int) -> String {
        switch self {
        case .deploymentFailed: "\(count) deployments failed"
        case .deploymentFinished, .deploymentFinishedElsewhere: "\(count) deployments finished"
        case .resourceDown: "\(count) resources stopped or turned unhealthy"
        case .backupFailed: "\(count) backups failed or are late"
        case .serverReachability: "\(count) servers changed reachability"
        }
    }
}

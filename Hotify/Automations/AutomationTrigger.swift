import Foundation

/// What starts a Shortcut automation. Every automatic trigger is one of the changes the instance watch already turns
/// into notifications, so it inherits their first-look baseline: nothing fires for the state things were in when
/// Hotify started looking.
enum AutomationTrigger: String, Codable, CaseIterable, Identifiable {
    /// A production deploy finished, wherever it started. Previews don't count.
    case deploymentSucceeded
    /// A production deploy failed.
    case deploymentFailed
    /// Something that ran stopped or turned unhealthy, unless this device stopped it.
    case resourceDown
    /// A database backup failed, or a schedule became late.
    case backupFailed
    /// Only when you tap Run. The one trigger iPhone offers.
    case manual

    var id: Self { self }

    var title: String {
        switch self {
        case .deploymentSucceeded: "Deployment succeeded"
        case .deploymentFailed: "Deployment failed"
        case .resourceDown: "Stopped or unhealthy"
        case .backupFailed: "Backup failed or overdue"
        case .manual: "Only when I tap Run"
        }
    }

    var detail: String {
        switch self {
        case .deploymentSucceeded: "A production deploy finished, from here, a push, or anywhere else."
        case .deploymentFailed: "A production deploy failed, wherever it started."
        case .resourceDown: "Something that ran stopped or turned unhealthy, unless you stopped it here."
        case .backupFailed: "A database backup failed, or one is late."
        case .manual: "Hotify never runs it on its own."
        }
    }

    var systemImage: String {
        switch self {
        case .deploymentSucceeded: "checkmark.seal"
        case .deploymentFailed: "exclamationmark.triangle"
        case .resourceDown: "flame"
        case .backupFailed: "externaldrive.badge.exclamationmark"
        case .manual: "hand.tap"
        }
    }

    /// The event's name in the JSON the Shortcut receives. Stable, since Shortcuts may branch on it.
    var payloadName: String {
        switch self {
        case .deploymentSucceeded: "deployment.succeeded"
        case .deploymentFailed: "deployment.failed"
        case .resourceDown: "resource.down"
        case .backupFailed: "backup.failed"
        case .manual: "manual"
        }
    }

    /// Whether Hotify runs it by itself when it sees the event.
    var isAutomatic: Bool { self != .manual }

    /// The notification events this trigger answers. A finished deploy is one event to an automation, whether this
    /// device started it or not.
    func answers(_ event: NotificationEvent) -> Bool {
        switch self {
        case .deploymentSucceeded: event == .deploymentFinished || event == .deploymentFinishedElsewhere
        case .deploymentFailed: event == .deploymentFailed
        case .resourceDown: event == .resourceDown
        case .backupFailed: event == .backupFailed
        case .manual: false
        }
    }

    /// Whether a resource of this kind can have the event. Only applications deploy, and only databases back up.
    func applies(to kind: ResourceKind) -> Bool {
        switch self {
        case .deploymentSucceeded, .deploymentFailed: kind == .application
        case .backupFailed: kind == .database
        case .resourceDown, .manual: true
        }
    }

    /// What this device can offer. Only the Mac keeps watching while its windows are closed, so iPhone runs a
    /// Shortcut when you tap Run and nothing else.
    static var available: [Self] {
        #if os(macOS)
        allCases
        #else
        [.manual]
        #endif
    }
}

import Foundation
import OSLog
import UserNotifications

/// Hands notices to the system, grouped per instance. When more than 3 of one kind arrive from one instance within a
/// minute, the rest fold into one summary that updates in place, so a server reboot doesn't send ten.
final class NotificationPoster {
    static let failedCategory = "deployment-failed"
    static let failedExplainableCategory = "deployment-failed-explainable"
    static let explainAction = "explain"
    static let rollbackAction = "rollback"

    private var recent: [String: [Date]] = [:]
    private var folded: [String: (count: Int, since: Date)] = [:]
    private let burstWindow: TimeInterval = 60
    private let burstSize = 3
    private static let log = Logger(subsystem: "com.sebastiankraatz.Hotify", category: "notifications")

    /// The actions on a failed deployment. Explain only where Apple Intelligence can answer.
    func registerCategories() {
        let rollback = UNNotificationAction(
            identifier: Self.rollbackAction, title: "Roll Back…", options: [.foreground])
        let explain = UNNotificationAction(identifier: Self.explainAction, title: "Explain", options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: Self.failedCategory, actions: [rollback], intentIdentifiers: []),
            UNNotificationCategory(
                identifier: Self.failedExplainableCategory, actions: [explain, rollback], intentIdentifiers: []),
        ])
    }

    func post(_ notice: Notice, instanceName: String, canExplain: Bool) {
        let key = "\(notice.instanceID.uuidString)-\(notice.event.rawValue)"
        let now = Date.now
        let window = (recent[key] ?? []).filter { now.timeIntervalSince($0) < burstWindow }
        guard window.count >= burstSize else {
            recent[key] = window + [now]
            add(identifier: UUID().uuidString, content: content(for: notice, canExplain: canExplain))
            return
        }
        recent[key] = window
        var fold: (count: Int, since: Date) = (0, now)
        if let earlier = folded[key], now.timeIntervalSince(earlier.since) < burstWindow { fold = earlier }
        fold.count += 1
        folded[key] = fold
        let summary = UNMutableNotificationContent()
        summary.title = instanceName
        summary.body = "\(notice.event.burst(window.count + fold.count)) in the last minute."
        summary.threadIdentifier = notice.instanceID.uuidString
        summary.interruptionLevel = notice.isTimeSensitive ? .timeSensitive : .active
        summary.userInfo = ["url": InstanceLink(instanceID: notice.instanceID).url.absoluteString]
        add(identifier: "burst-\(key)", content: summary)
    }

    private func content(for notice: Notice, canExplain: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        if let subtitle = notice.subtitle { content.subtitle = subtitle }
        content.body = notice.body
        content.sound = .default
        content.threadIdentifier = notice.instanceID.uuidString
        content.interruptionLevel = notice.isTimeSensitive ? .timeSensitive : .active
        var info = ["url": (notice.link ?? InstanceLink(instanceID: notice.instanceID).url).absoluteString]
        if let rollback = notice.rollbackLink { info["rollback"] = rollback.absoluteString }
        if let explain = notice.explainLink, canExplain { info["explain"] = explain.absoluteString }
        content.userInfo = info
        if notice.event == .deploymentFailed {
            content.categoryIdentifier =
                info["explain"] == nil ? Self.failedCategory : Self.failedExplainableCategory
        }
        return content
    }

    /// The system refuses a notification while Hotify isn't allowed to send any. Logged by kind, never by content.
    private func add(identifier: String, content: UNNotificationContent) {
        let category = content.categoryIdentifier
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        ) { error in
            if let error {
                Self.log.error(
                    "Notification refused (\(category, privacy: .public)): \(error.localizedDescription, privacy: .public)"
                )
            } else {
                Self.log.info("Notification posted (\(category, privacy: .public))")
            }
        }
    }
}

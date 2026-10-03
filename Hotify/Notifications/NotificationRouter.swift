import Foundation
import UserNotifications

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Shows notifications while Hotify is in front too, and opens what a click or an action points at. Everything goes
/// through a `hotify://` link, which opens the main window even when it was closed.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let key =
            switch response.actionIdentifier {
            case NotificationPoster.explainAction: "explain"
            case NotificationPoster.rollbackAction: "rollback"
            default: "url"
            }
        guard let text = (info[key] ?? info["url"]) as? String, let url = URL(string: text) else { return }
        await MainActor.run { Self.open(url) }
    }

    private static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
}

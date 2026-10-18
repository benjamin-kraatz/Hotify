import CoolifyAPI
import Foundation

/// Plain words for why reading or saving a channel failed. Nothing here repeats a value that was sent.
enum AlertFailure {
    static func loading(_ error: Error) -> String {
        guard let error = error as? CoolifyError else { return error.localizedDescription }
        if error.isUnauthenticated {
            return "Coolify didn’t accept this instance’s API token."
        }
        if error.isForbidden {
            return "Coolify didn’t let this token read alert settings. \(error.message)"
        }
        if error.isNotFound {
            return "This Coolify version has no API for alert settings. Update Coolify to manage them here."
        }
        return error.summary
    }

    static func saving(_ error: Error, channel: NotificationChannel) -> String {
        guard let error = error as? CoolifyError else { return error.localizedDescription }
        if error.isUnauthenticated {
            return "Coolify didn’t accept this instance’s API token, so nothing was saved."
        }
        if error.isForbidden {
            return
                "Coolify didn’t allow the change, so nothing was saved. Changing alerts needs a token with write access from a team admin or owner. \(error.message)"
        }
        if error.isNotFound {
            return "This Coolify version has no API for \(channel.title) alerts, so nothing was saved."
        }
        if error.isValidation {
            return "Coolify didn’t accept some values, so nothing was saved. Check the marked fields."
        }
        if let status = error.statusCode, (200..<300).contains(status) {
            return "Coolify answered, but Hotify couldn’t read what it saved. Close this and reload to check."
        }
        if error.statusCode == nil {
            return "Hotify couldn’t reach Coolify, so nothing was saved. \(error.message)"
        }
        return "Nothing was saved. \(error.summary)"
    }

    /// Coolify's messages for each field, joined. Unknown keys land under the empty key.
    static func fieldMessages(_ error: Error, channel: NotificationChannel) -> [String: String] {
        guard let error = error as? CoolifyError, error.isValidation else { return [:] }
        var messages: [String: String] = [:]
        for (key, lines) in error.fieldErrors {
            let target = channel.field(key) == nil ? "" : key
            let text = lines.joined(separator: " ")
            messages[target] = messages[target].map { "\($0) \(text)" } ?? text
        }
        return messages
    }
}

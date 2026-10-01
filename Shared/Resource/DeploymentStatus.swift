import Foundation

/// Reads Coolify's word for a deployment's state as heat and a label.
enum DeploymentStatus {
    static func heat(_ status: String) -> Heat {
        switch status {
        case "finished": .lit
        case "in_progress": .warming
        case "failed": .troubled
        case "queued": .unknown
        default: .cold
        }
    }

    static func label(_ status: String) -> String {
        switch status {
        case "finished": "Deployed"
        case "in_progress": "Deploying"
        case "failed": "Failed"
        case "queued": "Queued"
        case "cancelled-by-user": "Cancelled"
        default: status.prefix(1).uppercased() + status.dropFirst()
        }
    }

    /// Coolify is still working on it.
    static func isUnderway(_ status: String) -> Bool {
        status == "in_progress" || status == "queued"
    }
}

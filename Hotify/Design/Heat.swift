import CoolifyAPI
import SwiftUI

/// How alive something is. Hotify colors and animates every status through this.
///
/// Running is lit, in the brand red. Stopped is cold, a grey outline. Anything on its way up or down is warming,
/// and anything that needs a look is troubled. Both glow amber, so red never means broken.
enum Heat: Hashable, Comparable {
    case lit
    case warming
    case troubled
    case cold
    case unknown

    /// Reads a Coolify `state:health` status.
    init(status raw: String?) {
        guard let raw, !raw.isEmpty else {
            self = .unknown
            return
        }
        let status = ResourceStatus(raw: raw)
        switch status.state {
        case "running":
            self = status.health == "unhealthy" ? .troubled : .lit
        case "degraded":
            self = .troubled
        case "starting", "restarting":
            self = .warming
        case "exited", "stopped", "paused", "dead", "created":
            self = .cold
        default:
            self = .unknown
        }
    }

    /// The color for text and marks that stand for this heat.
    var tint: Color {
        switch self {
        case .lit: .ember
        case .warming, .troubled: .glow
        case .cold, .unknown: .secondary
        }
    }

    /// Warming and troubled want a look. Lit and cold are the quiet, expected states.
    var needsAttention: Bool {
        self == .warming || self == .troubled
    }
}

/// A short label for a raw Coolify status, such as `Healthy` for `running:healthy`.
enum StatusLabel {
    static func text(for raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "Unknown" }
        let status = ResourceStatus(raw: raw)
        if status.state == "running" {
            switch status.health {
            case "healthy": return "Healthy"
            case "unhealthy": return "Unhealthy"
            default: return "Running"
            }
        }
        return status.state.prefix(1).uppercased() + status.state.dropFirst()
    }

    /// The label while an action runs, from the request until a poll shows the result.
    static func text(for action: ResourceAction) -> String {
        switch action {
        case .start: "Starting…"
        case .deploy: "Deploying…"
        case .stop: "Stopping…"
        case .restart: "Restarting…"
        case .cancelDeployment: "Cancelling…"
        }
    }

    /// The label for a resource, in order of what matters most: an action of ours, a deployment, then Coolify's status.
    static func text(for resource: ResourceSummary, pendingAction: ResourceAction?) -> String {
        if let pendingAction {
            return text(for: pendingAction)
        }
        return resource.isDeploying ? "Deploying…" : text(for: resource.status)
    }
}

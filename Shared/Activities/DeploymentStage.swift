import Foundation

/// Where a deploy is, as a Live Activity shows it.
/// Not on the main actor, since it travels inside a Live Activity's state.
nonisolated enum DeploymentStage: String, Codable, Hashable {
    case queued
    case building
    case finished
    case failed
    case cancelled

    /// Reads a Coolify deployment status.
    init(status: String?) {
        switch status {
        case "queued": self = .queued
        case "finished": self = .finished
        case "failed": self = .failed
        case let status? where status.hasPrefix("cancelled"): self = .cancelled
        default: self = .building
        }
    }

    var isOver: Bool {
        self == .finished || self == .failed || self == .cancelled
    }

    /// A running deploy glows amber like anything starting. A failed one too, since red never means an error here.
    @MainActor var heat: Heat {
        switch self {
        case .queued, .building: .warming
        case .finished: .lit
        case .failed: .troubled
        case .cancelled: .cold
        }
    }

    var label: String {
        switch self {
        case .queued: "Waiting in the queue"
        case .building: "Deploying"
        case .finished: "Deployed"
        case .failed: "Deployment failed"
        case .cancelled: "Cancelled"
        }
    }
}

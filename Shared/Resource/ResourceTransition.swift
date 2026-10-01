import Foundation

/// An action Coolify accepted but has not finished.
///
/// Coolify answers start, stop, restart, and deploy as soon as it queues the work, before any container changes.
/// Hotify keeps the resource in its in-between state until a poll shows the result, so a start does not flash back
/// to "Exited" while Coolify is still building.
struct ResourceTransition: Codable, Hashable {
    var action: ResourceAction
    var startedAt: Date
    /// Coolify is still answering the request.
    var isSending = true
    var sawDeployment = false
    var deploymentEndedAt: Date?
    var sawChange = false

    /// How it ended, once it has.
    enum Outcome: Hashable {
        case done
        /// The resource never reached the state the action aims for.
        case gaveUp
    }

    init(action: ResourceAction, startedAt: Date = .now) {
        self.action = action
        self.startedAt = startedAt
    }

    /// Long enough for a slow image pull, short enough that a stuck row does not spin all day.
    private static let timeout: TimeInterval = 300
    /// Coolify updates a container's status on its own schedule, a little after the deployment ends.
    private static let settleAfterDeployment: TimeInterval = 30
    /// A restart of a running resource can finish between two polls without the status ever changing.
    private static let restartGrace: TimeInterval = 12

    /// Folds in one poll and says whether the transition is over.
    mutating func observe(status: String?, isDeploying: Bool, now: Date = .now) -> Outcome? {
        guard !isSending else { return nil }
        let heat = Heat(status: status)
        let isRunning = heat == .lit || heat == .troubled
        let elapsed = now.timeIntervalSince(startedAt)

        if isDeploying {
            sawDeployment = true
            deploymentEndedAt = nil
            return nil
        }
        if sawDeployment, deploymentEndedAt == nil {
            deploymentEndedAt = now
        }
        if heat != .lit {
            sawChange = true
        }

        let reached: Bool
        switch action {
        case .start:
            reached = isRunning
        case .stop:
            reached = heat == .cold
        case .restart:
            reached = isRunning && (sawChange || sawDeployment || elapsed >= Self.restartGrace)
        case .deploy:
            // A redeploy of a running app starts running and ends running. Only a finished deployment tells.
            reached = isRunning && (deploymentEndedAt != nil || (!sawDeployment && elapsed >= Self.restartGrace))
        case .cancelDeployment:
            reached = true
        }
        if reached {
            return .done
        }
        if let deploymentEndedAt, now.timeIntervalSince(deploymentEndedAt) >= Self.settleAfterDeployment {
            return .gaveUp
        }
        return !sawDeployment && elapsed >= Self.timeout ? .gaveUp : nil
    }
}

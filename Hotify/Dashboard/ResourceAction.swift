import Foundation

/// The resource an action runs on, so the dashboard can mark one row busy.
enum BusyTarget: Hashable {
    case application(String)
    case database(String)
    case service(String)
}

/// Something the user can ask Coolify to do with a resource.
enum ResourceAction: String, Identifiable, CaseIterable {
    case start
    case deploy
    case restart
    case stop
    case cancelDeployment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .start: "Start"
        case .deploy: "Redeploy"
        case .restart: "Restart"
        case .stop: "Stop"
        case .cancelDeployment: "Cancel Deployment"
        }
    }

    var systemImage: String {
        switch self {
        case .start: "play.fill"
        case .deploy: "arrow.triangle.2.circlepath"
        case .restart: "arrow.clockwise"
        case .stop: "stop.fill"
        case .cancelDeployment: "xmark"
        }
    }

    /// What the action does, for a tooltip or an accessibility hint.
    func explanation(for kind: ResourceKind) -> String {
        switch (self, kind) {
        case (.start, .application): "Build the latest commit and run it"
        case (.start, _): "Start the containers"
        case (.deploy, _): "Pull the latest commit, rebuild, and replace the running version"
        case (.restart, .application): "Restart the containers with the current build. Nothing is rebuilt."
        case (.restart, _): "Restart the containers"
        case (.stop, _): "Stop the containers. Volumes and data stay."
        case (.cancelDeployment, _): "Stop the build that is running now"
        }
    }

    /// Whether another action in flight holds this one back. A build can still be cancelled while Hotify waits on it.
    func isBlocked(by pending: ResourceAction?) -> Bool {
        guard let pending else { return false }
        return !(self == .cancelDeployment && pending != .cancelDeployment)
    }

    /// The actions that make sense for a resource right now, most likely first.
    ///
    /// A stopped application offers only Start: Coolify's start runs a full deployment, so a separate Deploy
    /// would do the same thing. A running one offers Redeploy to ship new code, and Restart to bounce what runs.
    static func available(for resource: ResourceSummary) -> [ResourceAction] {
        if resource.isDeploying {
            return resource.activeDeploymentID == nil ? [] : [.cancelDeployment]
        }
        switch resource.heat {
        case .cold:
            return [.start]
        case .unknown:
            return [.start, .restart, .stop]
        case .lit, .warming, .troubled:
            return resource.kind == .application ? [.deploy, .restart, .stop] : [.restart, .stop]
        }
    }
}

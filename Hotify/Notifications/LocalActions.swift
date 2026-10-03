import Foundation

/// What this device asked Coolify to do lately. It tells your own deploy from a push, and keeps a stop you made from
/// coming back as a notification. It lives in memory, since a notification only matters while Hotify runs.
enum LocalActions {
    enum Kind {
        /// A deploy, rollback, version, or preview, which starts a deployment.
        case deployment
        /// A start, stop, or restart, which changes whether the resource runs.
        case stateChange
    }

    private static var entries: [ResourceRoute: [(kind: Kind, at: Date)]] = [:]

    static func note(_ kind: Kind, _ route: ResourceRoute) {
        let cutoff = Date.now.addingTimeInterval(-3_600)
        entries[route, default: []].removeAll { $0.at < cutoff }
        entries[route, default: []].append((kind, .now))
    }

    /// Notes what a resource action does. Starting an application deploys it, too.
    static func note(_ action: ResourceAction, _ route: ResourceRoute) {
        switch action {
        case .deploy:
            note(Kind.deployment, route)
        case .start:
            note(Kind.stateChange, route)
            if route.kind == .application { note(Kind.deployment, route) }
        case .stop, .restart:
            note(Kind.stateChange, route)
        case .cancelDeployment:
            break
        }
    }

    /// Whether this device deployed the resource since `date`.
    static func deployed(_ route: ResourceRoute, since date: Date) -> Bool {
        entries[route]?.contains { $0.kind == .deployment && $0.at >= date } ?? false
    }

    /// Whether this device started, stopped, restarted, or deployed the resource in the last `interval`.
    static func touched(_ route: ResourceRoute, within interval: TimeInterval) -> Bool {
        let cutoff = Date.now.addingTimeInterval(-interval)
        return entries[route]?.contains { $0.at >= cutoff } ?? false
    }
}

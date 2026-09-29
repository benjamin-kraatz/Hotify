import Foundation

/// Everything the dashboard column shows, as plain values. `DashboardModel` builds it; previews write one by hand.
struct DashboardSnapshot: Hashable {
    var teamName = ""
    var version = ""
    var servers: [ServerLine] = []
    var resources: [ResourceSummary] = []
    var pending: [BusyTarget: ResourceAction] = [:]
    var loadError: String?
    var actionError: String?
    var isLoading = false
    var hasLoaded = false

    func resource(_ route: ResourceRoute) -> ResourceSummary? {
        resources.first { $0.route == route }
    }

    func pendingAction(for route: ResourceRoute) -> ResourceAction? {
        pending[route.busyTarget]
    }
}

/// One server and whether Coolify can reach it.
struct ServerLine: Identifiable, Hashable {
    var id: String
    var name: String
    var isReachable: Bool?
}

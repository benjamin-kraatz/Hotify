import Foundation

/// What a widget last read about one resource. Kept between timelines, so a failed read still has a name to show.
struct ResourceReading: Codable, Hashable {
    var name: String
    var subtitle: String?
    var instanceName: String
    var status: String?
    var isDeploying = false
    var activeDeploymentID: String?
    /// When Coolify last answered for this resource.
    var checkedAt: Date?
    /// Why the last read failed. A reading with a problem shows no heat, since the status may be old.
    var problem: ReadingProblem?

    init(summary: ResourceSummary, instanceName: String, checkedAt: Date) {
        name = summary.name
        subtitle = summary.subtitle
        self.instanceName = instanceName
        status = summary.status
        isDeploying = summary.isDeploying
        activeDeploymentID = summary.activeDeploymentID
        self.checkedAt = checkedAt
    }

    init(name: String, instanceName: String, problem: ReadingProblem) {
        self.name = name
        self.instanceName = instanceName
        self.problem = problem
    }

    func summary(for route: ResourceRoute) -> ResourceSummary {
        ResourceSummary(
            route: route,
            name: name,
            status: status,
            subtitle: subtitle,
            isDeploying: isDeploying,
            activeDeploymentID: activeDeploymentID
        )
    }
}

/// Why a widget could not read a resource.
enum ReadingProblem: String, Codable, Hashable {
    /// The instance was removed in Hotify.
    case noInstance
    /// The token is not on this device yet, or the Keychain is locked.
    case noToken
    /// Coolify no longer lists the resource.
    case gone
    /// The request failed: offline, a timeout, or an error from Coolify.
    case unreachable

    func message(instanceName: String) -> String {
        switch self {
        case .noInstance: "Instance removed"
        case .noToken: "No token yet"
        case .gone: "Gone from Coolify"
        case .unreachable: instanceName.isEmpty ? "Can't reach Coolify" : "Can't reach \(instanceName)"
        }
    }
}

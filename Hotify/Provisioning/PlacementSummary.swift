import CoolifyAPI
import Foundation

/// Where a new resource lands, said the same way at the foot of every launch pad.
enum PlacementSummary {
    static func text(_ placement: PlacementModel, then outcome: String) -> String {
        guard let server = placement.server, let project = placement.project, let environment = placement.environment
        else { return "Pick a server, project, and environment." }
        return "On \(server.name), in \(project.name ?? project.uuid) · \(environment.name ?? ""). \(outcome)"
    }
}

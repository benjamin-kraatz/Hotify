import CoolifyAPI
import Foundation

/// The project and environment a resource lives in.
struct ResourcePlace: Hashable {
    /// The project's uuid, which opens its page.
    var projectID: String
    var projectName: String
    var environmentName: String
    /// Orders environments the way Coolify creates them, so production usually leads.
    var environmentID: Int
    /// Keys the environment's color. `nil` when Coolify sent the environment without one.
    var environmentUUID: String?

    /// Maps Coolify environment ids to places. Needs projects fetched one by one; the list omits environments.
    static func index(_ projects: [Project]) -> [Int: ResourcePlace] {
        var places: [Int: ResourcePlace] = [:]
        for project in projects {
            let projectName = project.name.flatMap { $0.isEmpty ? nil : $0 } ?? project.uuid
            for environment in project.environments ?? [] {
                guard let id = environment.id else { continue }
                places[id] = ResourcePlace(
                    projectID: project.uuid,
                    projectName: projectName,
                    environmentName: environment.name ?? "",
                    environmentID: id,
                    environmentUUID: environment.uuid.flatMap { $0.isEmpty ? nil : $0 }
                )
            }
        }
        return places
    }
}

extension [ResourceSummary] {
    /// Applications first, then services, then databases, each by name. Every list of resources uses this order.
    func sortedForDisplay() -> [ResourceSummary] {
        let kindOrder: [ResourceKind] = [.application, .service, .database]
        return sorted { lhs, rhs in
            let lhsKind = kindOrder.firstIndex(of: lhs.kind) ?? 0
            let rhsKind = kindOrder.firstIndex(of: rhs.kind) ?? 0
            if lhsKind != rhsKind {
                return lhsKind < rhsKind
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

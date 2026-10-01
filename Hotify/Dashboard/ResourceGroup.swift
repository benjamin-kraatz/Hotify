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
                    environmentID: id
                )
            }
        }
        return places
    }
}

/// A dashboard section: the resources in one environment of one project.
struct ResourceGroup: Identifiable, Hashable {
    /// `nil` for resources Hotify could not place, such as one created since the projects last loaded.
    var place: ResourcePlace?
    var resources: [ResourceSummary]

    var id: Int { place?.environmentID ?? -1 }

    /// Sorts projects by name and environments by age. Within a group, applications come first, then services,
    /// then databases, each by name.
    static func grouping(_ resources: [ResourceSummary]) -> [ResourceGroup] {
        Dictionary(grouping: resources, by: \.place)
            .map { place, members in
                ResourceGroup(place: place, resources: sorted(members))
            }
            .sorted { lhs, rhs in
                switch (lhs.place, rhs.place) {
                case (let left?, let right?):
                    let order = left.projectName.localizedStandardCompare(right.projectName)
                    return order == .orderedSame ? left.environmentID < right.environmentID : order == .orderedAscending
                case (.some, nil):
                    return true
                case (nil, _):
                    return false
                }
            }
    }

    /// Applications first, then services, then databases, each by name.
    static func sorted(_ resources: [ResourceSummary]) -> [ResourceSummary] {
        let kindOrder: [ResourceKind] = [.application, .service, .database]
        return resources.sorted { lhs, rhs in
            let lhsKind = kindOrder.firstIndex(of: lhs.kind) ?? 0
            let rhsKind = kindOrder.firstIndex(of: rhs.kind) ?? 0
            if lhsKind != rhsKind {
                return lhsKind < rhsKind
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

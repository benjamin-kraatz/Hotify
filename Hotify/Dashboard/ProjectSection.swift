import Foundation

/// One project in the dashboard list, with its resources by environment.
struct ProjectSection: Identifiable, Hashable {
    /// The project's uuid. `nil` for the resources Hotify could not place, such as one created since the projects
    /// last loaded.
    var projectID: String?
    var name: String
    /// Oldest first, the order Coolify creates them in. Only environments that have something to show.
    var environments: [EnvironmentSection] = []

    var id: String { projectID ?? "other" }

    var resources: [ResourceSummary] { environments.flatMap(\.resources) }

    /// With several environments each one gets its own label inside the section.
    var labelsEnvironments: Bool { environments.count > 1 }

    /// With one environment its name rides along beside the project's instead.
    var soleEnvironmentName: String? {
        guard environments.count == 1, let name = environments.first?.name, !name.isEmpty else { return nil }
        return name
    }

    /// The project, then its resources, in the order the list shows them. What the arrow keys step through.
    var routes: [DetailRoute] {
        (projectID.map { [DetailRoute.project($0)] } ?? []) + resources.map { .resource($0.route) }
    }
}

/// One environment of a project in the dashboard list.
struct EnvironmentSection: Identifiable, Hashable {
    var id: Int
    var name: String
    var resources: [ResourceSummary]
}

extension ProjectSection {
    /// Groups resources under their projects, by name, with the unplaced ones last.
    ///
    /// `projects` supplies current names and the projects that hold nothing. Those only show when `includesEmpty`
    /// is set, which a filter turns off: a project with nothing in it matches no filter.
    static func sections(
        of resources: [ResourceSummary], projects: [ProjectSummary], includesEmpty: Bool
    ) -> [ProjectSection] {
        let names = Dictionary(projects.map { ($0.id, $0.name) }) { first, _ in first }
        var sections = Dictionary(grouping: resources) { $0.place?.projectID }
            .map { projectID, members in
                ProjectSection(
                    projectID: projectID,
                    name: projectID.map { names[$0] ?? members.first?.place?.projectName ?? $0 } ?? "Other",
                    environments: Dictionary(grouping: members) { $0.place?.environmentID ?? -1 }
                        .map { id, members in
                            EnvironmentSection(
                                id: id,
                                name: members.first?.place?.environmentName ?? "",
                                resources: members.sortedForDisplay()
                            )
                        }
                        .sorted { $0.id < $1.id }
                )
            }
        if includesEmpty {
            let shown = Set(sections.compactMap(\.projectID))
            sections += projects.filter { !shown.contains($0.id) }.map {
                ProjectSection(projectID: $0.id, name: $0.name)
            }
        }
        return sections.sorted { lhs, rhs in
            switch (lhs.projectID, rhs.projectID) {
            case (.some, nil): return true
            case (nil, _): return false
            case (.some, .some):
                let order = lhs.name.localizedStandardCompare(rhs.name)
                return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
            }
        }
    }
}

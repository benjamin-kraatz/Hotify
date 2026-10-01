import SwiftUI

/// One project in the Mac's dashboard column: its head, then a panel per environment with that environment's
/// resources.
///
/// The head stands on the column itself and opens the project. Each panel is one environment, named at its top,
/// so what belongs together shares a panel and a project's name shows once however many environments it has.
struct ProjectGroup<Row: View>: View {
    var section: ProjectSection
    /// Each resource's heat as the list shows it, by route.
    var heat: (ResourceSummary) -> Heat
    var selection: DetailRoute?
    var onSelect: (DetailRoute) -> Void
    /// A resource's row, without the highlight and the click. The group adds those.
    @ViewBuilder var row: (ResourceSummary) -> Row

    @SwiftUI.Environment(\.placePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            head

            ForEach(section.environments) { environment in
                panel(environment)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var head: some View {
        let header = ProjectSectionHeader(
            section: section, heats: section.resources.map(heat), tint: palette.project(section.projectID)
        )
        .padding(.vertical, 8)
        if let projectID = section.projectID {
            let route = DetailRoute.project(projectID)
            DashboardRowButton(isSelected: selection == route) {
                onSelect(route)
            } label: {
                header
            }
            .id(route)
            .help("Show the \(section.name) project")
            .accessibilityHint("Shows the project")
            // In line with the rows inside the panels below.
            .padding(.horizontal, 4)
        } else {
            header
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4 + DashboardRowMetrics.inset)
        }
    }

    private func panel(_ environment: EnvironmentSection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Resources Hotify could not place have no environment to name.
            if section.projectID != nil {
                EnvironmentHeading(
                    name: environment.name,
                    heats: environment.resources.map(heat),
                    tint: palette.environment(environment.uuid)
                )
                .padding(.horizontal, DashboardRowMetrics.inset)
                .padding(.top, 7)
                .padding(.bottom, 5)
            }
            ForEach(environment.resources) { resource in
                let route = DetailRoute.resource(resource.route)
                DashboardRowButton(isSelected: selection == route) {
                    onSelect(route)
                } label: {
                    row(resource)
                }
                .id(route)
                .transition(.opacity)
            }
        }
        // Rows keep this far from the panel's edge, so a highlighted one reads as a pill inside it.
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .well()
    }
}

enum DashboardRowMetrics {
    /// How far a row's content sits from the edge of its highlight.
    static let inset: CGFloat = 10
}

/// A row of the Mac's dashboard column that opens something. It shows where the pointer is, and which row is open
/// in the detail column, as a tinted pill rather than a filled one, so the flames keep their own colors.
struct DashboardRowButton<Label: View>: View {
    var isSelected: Bool
    var action: () -> Void
    @ViewBuilder var label: Label

    @State private var isHovered = false

    private var fill: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(.tint.opacity(0.18))
        }
        return AnyShapeStyle(Color.primary.opacity(isHovered ? 0.05 : 0))
    }

    var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, DashboardRowMetrics.inset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(fill, in: .rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.tint.opacity(isSelected ? 0.4 : 0), lineWidth: 1)
                }
                .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.15), value: isHovered)
        .animation(.snappy(duration: 0.2), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var selection: DetailRoute? = .resource(.application("web"))
    let production = ResourcePlace(
        projectID: "website", projectName: "Website", environmentName: "production", environmentID: 1)
    let staging = ResourcePlace(
        projectID: "website", projectName: "Website", environmentName: "staging", environmentID: 2)
    let resources = [
        ResourceSummary(
            route: .application("web"), name: "marketing-site", status: "running:healthy",
            subtitle: "hotify.example.com", place: production),
        ResourceSummary(
            route: .database("pg"), name: "postgres", status: "running:unhealthy", subtitle: "PostgreSQL",
            place: production),
        ResourceSummary(
            route: .application("web-staging"), name: "marketing-site", status: "exited",
            subtitle: "staging.hotify.example.com", place: staging),
    ]
    VStack(alignment: .leading, spacing: 22) {
        ProjectGroup(
            section: ProjectSection(
                projectID: "website",
                name: "Website",
                environments: [
                    EnvironmentSection(id: 1, name: "production", resources: Array(resources.prefix(2))),
                    EnvironmentSection(id: 2, name: "staging", resources: Array(resources.suffix(1))),
                ]
            ),
            heat: \.heat,
            selection: selection,
            onSelect: { selection = $0 }
        ) { resource in
            ResourceRow(resource: resource)
        }
        ProjectGroup(
            section: ProjectSection(projectID: "new", name: "Side project"),
            heat: \.heat,
            selection: selection,
            onSelect: { selection = $0 }
        ) { resource in
            ResourceRow(resource: resource)
        }
    }
    .padding(16)
    .frame(width: 400)
}

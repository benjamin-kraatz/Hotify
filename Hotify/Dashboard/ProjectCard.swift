import SwiftUI

/// One project in the Mac's dashboard column: a panel with the project on top and its resources underneath.
///
/// The panel is what says these belong together, so the project's name shows once however many environments it
/// has. The head opens the project. Each row opens its resource.
struct ProjectCard<Row: View>: View {
    var section: ProjectSection
    var heats: [Heat]
    var selection: DetailRoute?
    var onSelect: (DetailRoute) -> Void
    /// A resource's row, without the highlight and the click. The card adds those.
    @ViewBuilder var row: (ResourceSummary) -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            head

            ForEach(section.environments) { environment in
                if section.labelsEnvironments {
                    EnvironmentBadge(name: environment.name.isEmpty ? "Environment" : environment.name)
                        .padding(.leading, DashboardRowMetrics.inset)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                        .accessibilityAddTraits(.isHeader)
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
        }
        // Rows keep this far from the panel's edge, so a highlighted one reads as a pill inside it.
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .well()
    }

    @ViewBuilder
    private var head: some View {
        let header = ProjectSectionHeader(section: section, heats: heats)
            .padding(.vertical, 6)
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
        } else {
            header
                .foregroundStyle(.secondary)
                .padding(.horizontal, DashboardRowMetrics.inset)
        }
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
    VStack(spacing: 14) {
        ProjectCard(
            section: ProjectSection(
                projectID: "website",
                name: "Website",
                environments: [
                    EnvironmentSection(id: 1, name: "production", resources: Array(resources.prefix(2))),
                    EnvironmentSection(id: 2, name: "staging", resources: Array(resources.suffix(1))),
                ]
            ),
            heats: [.lit, .troubled, .cold],
            selection: selection,
            onSelect: { selection = $0 }
        ) { resource in
            ResourceRow(resource: resource)
        }
        ProjectCard(
            section: ProjectSection(projectID: "new", name: "Side project"),
            heats: [],
            selection: selection,
            onSelect: { selection = $0 }
        ) { resource in
            ResourceRow(resource: resource)
        }
    }
    .padding(16)
    .frame(width: 400)
}

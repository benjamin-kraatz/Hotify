import SwiftUI

/// The project's resources, one panel per environment, then what was deployed lately.
struct ProjectOverview: View {
    var project: ProjectSummary
    var resources: [ResourceSummary]
    var pending: [BusyTarget: ResourceAction] = [:]
    /// The newest production deployments across the project's applications.
    var deployments: [ProjectDeployment] = []
    /// The history is still on its way, so a missing list of deployments is not yet an empty one.
    var isLoadingDeployments = false
    var onOpen: (ResourceSummary) -> Void
    var onOpenDeployment: (ProjectDeployment) -> Void = { _ in }
    var onAction: (ResourceAction, ResourceSummary) -> Void = { _, _ in }
    /// `nil` leaves the environment controls out, as without a connection.
    var onEditEnvironment: ((EnvironmentSummary) -> Void)?
    /// Creates an environment by name, with its color. `nil` leaves the button out, as without a connection.
    var onAddEnvironment: ((_ name: String, _ tint: PlaceTint?) async throws -> Void)?

    @State private var stopCandidate: ResourceSummary?
    @State private var isAddingEnvironment = false
    @SwiftUI.Environment(\.placePalette) private var palette

    private var groups: [EnvironmentGroup] {
        let members = Dictionary(grouping: resources) { $0.place?.environmentID ?? -1 }
        let known = Set(project.environments.map(\.id))
        var groups = project.environments.map { environment in
            EnvironmentGroup(
                environment: environment,
                resources: (members[environment.id] ?? []).sortedForDisplay(),
                isListed: true
            )
        }
        // A resource can name an environment before the project lists it, when the environment is minutes old.
        for id in members.keys.sorted() where !known.contains(id) {
            let resources = members[id] ?? []
            groups.append(
                EnvironmentGroup(
                    environment: EnvironmentSummary(
                        id: id,
                        uuid: resources.first?.place?.environmentUUID,
                        name: resources.first?.place?.environmentName ?? ""
                    ),
                    resources: resources.sortedForDisplay(),
                    isListed: false
                )
            )
        }
        return groups
    }

    private var hasApplications: Bool {
        resources.contains { $0.kind == .application }
    }

    var body: some View {
        let groups = groups
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(groups) { group in
                    environmentPanel(group)
                }

                if let onAddEnvironment, !groups.isEmpty {
                    Button("New Environment…", systemImage: "plus") {
                        isAddingEnvironment = true
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline.weight(.medium))
                    .help("Add an empty environment to \(project.name)")
                    .popover(isPresented: $isAddingEnvironment, arrowEdge: .bottom) {
                        newEnvironment(onAddEnvironment)
                    }
                }

                if !deployments.isEmpty {
                    deploymentsPanel
                        .transition(.opacity)
                } else if isLoadingDeployments, hasApplications {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading deployments…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView {
                    Label("Nothing here yet", systemImage: "flame")
                } description: {
                    Text("\(project.name) has no resources. Create one in Coolify and it shows up here.")
                } actions: {
                    if let onAddEnvironment {
                        Button("New Environment…") {
                            isAddingEnvironment = true
                        }
                        .glassButton()
                        .popover(isPresented: $isAddingEnvironment, arrowEdge: .bottom) {
                            newEnvironment(onAddEnvironment)
                        }
                    }
                }
            }
        }
        .stopConfirmation(for: $stopCandidate) { resource in
            onAction(.stop, resource)
        }
        .animation(.snappy, value: groups.map(\.id))
        .animation(.snappy, value: resources.map(\.id))
        .animation(.snappy, value: deployments.map(\.id))
        .animation(.snappy, value: isLoadingDeployments)
    }

    private func newEnvironment(_ onAdd: @escaping (String, PlaceTint?) async throws -> Void) -> some View {
        NewPlacePopover(
            kind: .environment,
            note: "It starts empty in \(project.name). Resources are created in it from Coolify.",
            takenNames: Set(project.environments.map(\.name)),
            onAdd: onAdd
        )
    }

    // MARK: Environments

    private func environmentPanel(_ group: EnvironmentGroup) -> some View {
        let heats = group.resources.map { $0.heat(pendingAction: pending[$0.route.busyTarget]) }
        let running = heats.count { $0 == .lit }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    PlaceMark(tint: palette.environment(group.environment.uuid))
                    Text(group.environment.name.isEmpty ? "Environment" : group.environment.name)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .font(.headline)
                if let description = group.environment.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if !heats.isEmpty {
                    Text("\(running) of \(heats.count) running")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                if let onEditEnvironment, group.isListed {
                    Menu {
                        Button("Edit Environment…", systemImage: "pencil") {
                            onEditEnvironment(group.environment)
                        }
                    } label: {
                        Label("More for \(group.environment.name)", systemImage: "ellipsis")
                            .labelStyle(.iconOnly)
                            // Taller than the glyph, so the three dots are not a sliver to hit.
                            .frame(minHeight: 18)
                            .contentShape(.rect)
                    }
                    .menuIndicator(.hidden)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .help("Rename or describe this environment")
                }
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                if group.resources.isEmpty {
                    Text("Nothing is deployed here yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                ForEach(Array(group.resources.enumerated()), id: \.element.id) { index, resource in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 42)
                    }
                    row(resource)
                }
            }
            .well()
            .clipShape(.rect(cornerRadius: 14))
        }
    }

    private func row(_ resource: ResourceSummary) -> some View {
        let pendingAction = pending[resource.route.busyTarget]
        return ProjectRow {
            onOpen(resource)
        } label: {
            ResourceRow(resource: resource, pendingAction: pendingAction, centersStatus: true)
        }
        .accessibilityHint("Shows \(resource.name)")
        .contextMenu {
            ResourceActionButtons(resource: resource, pendingAction: pendingAction) { action in
                if action == .stop {
                    stopCandidate = resource
                } else {
                    onAction(action, resource)
                }
            }
            if let link = resource.link {
                Divider()
                Link(destination: link) {
                    Label("Open \(link.host() ?? link.absoluteString)", systemImage: "safari")
                }
            }
        }
    }

    // MARK: Deployments

    private var deploymentsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent deployments")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(deployments.enumerated()), id: \.element.id) { index, deployment in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 42)
                    }
                    ProjectRow {
                        onOpenDeployment(deployment)
                    } label: {
                        ProjectDeploymentRow(deployment: deployment)
                    }
                    .accessibilityHint("Shows the deployments of \(deployment.applicationName)")
                }
            }
            .well()
            .clipShape(.rect(cornerRadius: 14))
        }
    }
}

/// One environment of the project with what lives in it.
private struct EnvironmentGroup: Identifiable {
    var environment: EnvironmentSummary
    var resources: [ResourceSummary]
    /// Whether the project itself lists the environment, so it can be edited.
    var isListed: Bool

    var id: Int { environment.id }
}

/// A row in one of the page's panels that leads somewhere: its content, a chevron, and a highlight under the pointer.
private struct ProjectRow<Content: View>: View {
    var action: () -> Void
    @ViewBuilder var label: Content

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                label
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(isHovered ? 0.045 : 0))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.15), value: isHovered)
    }
}

/// One production deployment: the application, how it went, what shipped, and when.
private struct ProjectDeploymentRow: View {
    var deployment: ProjectDeployment

    @SwiftUI.Environment(\.placePalette) private var palette

    private var line: DeploymentLine { deployment.line }

    var body: some View {
        // The outcome and the time form one trailing block, centered on the row like the chevron after it.
        // A deployment without a time leaves the outcome alone there, still in line with the chevron.
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                FlameGlyph(heat: line.heat, height: 17)
                    .frame(width: 16)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(deployment.applicationName)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let environment = deployment.environmentName, !environment.isEmpty {
                            EnvironmentBadge(name: environment, tint: palette.environment(deployment.environmentUUID))
                        }
                        if line.isRestart {
                            Tag(text: "Restart")
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let commit = line.commit {
                            Text(commit)
                                .font(.caption.monospaced())
                        }
                        Text(line.message ?? (line.commit == nil ? "No commit message" : ""))
                            .lineLimit(1)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 3) {
                Text(line.statusLabel)
                    .foregroundStyle(line.heat.needsAttention ? AnyShapeStyle(.glow) : AnyShapeStyle(.secondary))
                    .contentTransition(.interpolate)
                if let startedAt = line.startedAt {
                    Text(startedAt, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                        .help(startedAt.formatted(date: .abbreviated, time: .standard))
                }
            }
            .font(.subheadline)
            .lineLimit(1)
            .layoutPriority(1)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let now = Date.now
    let production = ResourcePlace(
        projectID: "website", projectName: "Website", environmentName: "production", environmentID: 1,
        environmentUUID: "env-prod")
    ProjectOverview(
        project: ProjectSummary(
            id: "website",
            name: "Website",
            environments: [
                EnvironmentSummary(id: 1, uuid: "env-prod", name: "production", description: "What customers see"),
                EnvironmentSummary(id: 2, uuid: "env-staging", name: "staging"),
            ]
        ),
        resources: [
            ResourceSummary(
                route: .application("web"),
                name: "marketing-site",
                status: "running:healthy",
                subtitle: "hotify.example.com",
                place: production,
                buildingPreviews: [42]
            ),
            ResourceSummary(
                route: .application("api"),
                name: "api",
                status: "exited",
                subtitle: "example/api",
                place: production,
                isDeploying: true
            ),
            ResourceSummary(
                route: .database("pg"),
                name: "postgres",
                status: "running:unhealthy",
                subtitle: "PostgreSQL",
                place: production
            ),
        ],
        pending: [.database("pg"): .restart],
        deployments: [
            ProjectDeployment(
                applicationUUID: "api",
                applicationName: "api",
                line: DeploymentLine(
                    id: "3", status: "in_progress", commit: "9f2c1ab", message: "feat: rate limits",
                    startedAt: now.addingTimeInterval(-40))
            ),
            ProjectDeployment(
                applicationUUID: "web",
                applicationName: "marketing-site",
                line: DeploymentLine(
                    id: "2", status: "finished", commit: "abc1234", message: "fix: login redirect",
                    startedAt: now.addingTimeInterval(-3_600), finishedAt: now.addingTimeInterval(-3_528))
            ),
            ProjectDeployment(
                applicationUUID: "web",
                applicationName: "marketing-site",
                line: DeploymentLine(
                    id: "1", status: "failed", commit: "77aa01e", message: "chore: bump node to 24",
                    startedAt: now.addingTimeInterval(-86_400))
            ),
        ],
        onOpen: { _ in },
        onEditEnvironment: { _ in },
        onAddEnvironment: { _, _ in }
    )
    .frame(width: 600, height: 640)
    .environment(\.placePalette, .preview(environments: ["env-prod": .orange, "env-staging": .indigo]))
}

#Preview("Empty") {
    ProjectOverview(
        project: ProjectSummary(id: "new", name: "Side project"),
        resources: [],
        onOpen: { _ in },
        onAddEnvironment: { _, _ in }
    )
    .frame(width: 600, height: 420)
}

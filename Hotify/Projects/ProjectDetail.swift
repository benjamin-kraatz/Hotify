import CoolifyAPI
import SwiftUI

/// One project: its resources by environment, its previews, and the variables it shares. While it is on screen it
/// reads the deployment history of the project's applications, which is where the previews come from.
struct ProjectDetailScreen: View {
    var client: CoolifyClient?
    /// The tab and what the page has loaded, kept by the window so they outlast a visit to one of the resources.
    var page: ProjectPageModel
    /// Tells this project from every other, across instances too.
    var key: AnyHashable
    var project: ProjectSummary
    var resources: [ResourceSummary]
    var pending: [BusyTarget: ResourceAction]
    /// The last action that failed, from the dashboard. The middle column is off screen on iPhone.
    var actionError: String?
    var onOpen: (ResourceRoute, ResourceEntry?) -> Void
    var onAction: (ResourceAction, ResourceRoute) -> Void
    /// Reloads the dashboard's projects, after a rename or a new environment.
    var onChanged: () async -> Void
    /// Opens the New Service sheet in this project. `nil` hides the button, such as before the instance connects.
    var onNewService: (() -> Void)?

    @SwiftUI.Environment(\.placePalette) private var palette

    private var activity: ProjectActivityModel { page.activity }

    private var applicationUUIDs: [String] {
        resources.compactMap { resource in
            if case .application(let uuid) = resource.route { uuid } else { nil }
        }
    }

    /// Changes whenever a deployment or a preview build starts or ends, which is when the history is worth reading.
    private var builds: [BuildSignal] {
        resources.map { BuildSignal(isDeploying: $0.isDeploying, previews: $0.buildingPreviews) }
    }

    var body: some View {
        ProjectDetail(
            project: project,
            resources: resources,
            pending: pending,
            actionError: actionError,
            page: page,
            canEdit: client != nil,
            onOpen: onOpen,
            onAction: onAction,
            onSaveProject: saveProject,
            onAddEnvironment: addEnvironment,
            onSaveEnvironment: saveEnvironment,
            onReload: reload,
            onNewService: onNewService
        )
        // Before the first frame, so a page left on another project never shows that project's tab or history.
        .onAppear {
            guard let client else { return }
            page.open(key, project: project, client: client)
            activity.applications = applicationUUIDs
        }
        .task(id: key) {
            // One request per application, so this polls far slower than the dashboard does. A build starting or
            // ending still refreshes it at once, below.
            while !Task.isCancelled {
                await activity.refresh()
                if Task.isCancelled { return }
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .onChange(of: applicationUUIDs) { _, uuids in
            activity.applications = uuids
            Task { await activity.refresh() }
        }
        .onChange(of: builds) { _, _ in
            Task { await activity.refresh() }
        }
        .onChange(of: project) { _, project in
            page.variables.track(project)
        }
    }

    private func saveProject(name: String, description: String) async throws {
        try await write { client in
            _ = try await client.updateProject(project.id, name: name, description: description)
        }
    }

    private func addEnvironment(name: String, tint: PlaceTint?) async throws {
        try await write { client in
            let created = try await client.createEnvironment(name: name, inProject: project.id)
            if let tint {
                palette.setEnvironment(tint, for: created.uuid)
            }
        }
    }

    private func saveEnvironment(_ environment: EnvironmentSummary, name: String, description: String) async throws {
        try await write { client in
            _ = try await client.updateEnvironment(
                environment.reference, inProject: project.id, name: name, description: description)
        }
    }

    /// Sends one change, then reloads the projects so the page shows it.
    private func write(_ change: (CoolifyClient) async throws -> Void) async throws {
        guard let client else {
            throw PlaceWriteError(message: "Hotify is not connected to this instance.")
        }
        do {
            try await change(client)
        } catch {
            throw PlaceWriteError(error)
        }
        await onChanged()
    }

    private func reload() async {
        async let dashboard: Void = onChanged()
        async let history: Void = activity.refresh()
        async let shared: Void = page.variables.load()
        _ = await (dashboard, history, shared)
    }
}

/// What one resource is building right now.
private struct BuildSignal: Hashable {
    var isDeploying: Bool
    var previews: [Int]
}

/// The project page's layout. Takes plain values, and models without a client, so a preview does not need one.
struct ProjectDetail: View {
    var project: ProjectSummary
    var resources: [ResourceSummary]
    var pending: [BusyTarget: ResourceAction] = [:]
    var actionError: String?
    var page: ProjectPageModel
    /// Whether there is a connection to send a rename or a new environment over.
    var canEdit = false
    var onOpen: (ResourceRoute, ResourceEntry?) -> Void = { _, _ in }
    var onAction: (ResourceAction, ResourceRoute) -> Void = { _, _ in }
    var onSaveProject: (_ name: String, _ description: String) async throws -> Void = { _, _ in }
    var onAddEnvironment: (_ name: String, _ tint: PlaceTint?) async throws -> Void = { _, _ in }
    var onSaveEnvironment: (EnvironmentSummary, _ name: String, _ description: String) async throws -> Void = {
        _, _, _ in
    }
    var onReload: () async -> Void = {}
    /// `nil` hides the New Service button.
    var onNewService: (() -> Void)?

    @State private var sheet: ProjectSheet?
    /// The popover at the toolbar menu. The overview has one of its own at its button.
    @State private var isAddingEnvironment = false
    @State private var reloads = 0
    @SwiftUI.Environment(\.placePalette) private var palette

    private var activity: ProjectActivityModel { page.activity }

    private var applications: [ResourceSummary] {
        resources.filter { $0.kind == .application }.sortedForDisplay()
    }

    /// Only applications have previews, so a project of databases and services goes without the tab.
    private var tabs: [ProjectTab] {
        applications.isEmpty ? [.overview, .variables] : [.overview, .previews, .variables]
    }

    private var currentTab: ProjectTab {
        tabs.contains(page.tab) ? page.tab : .overview
    }

    private var heats: [Heat] {
        resources.map { $0.heat(pendingAction: pending[$0.route.busyTarget]) }
    }

    /// With one environment its name adds nothing. With several, it tells two applications of one name apart.
    private var namesEnvironments: Bool {
        Set(resources.compactMap { $0.place?.environmentID }).count > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProjectHeader(project: project, heats: heats, tint: palette.project(project.id))
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 18)

            VStack(spacing: 8) {
                if let actionError {
                    NoticeBanner(message: actionError)
                }
                if let loadError = activity.loadError {
                    NoticeBanner(message: loadError)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, actionError == nil && activity.loadError == nil ? 0 : 12)

            Picker("Show", selection: Binding(get: { currentTab }, set: { page.tab = $0 })) {
                ForEach(tabs) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            Group {
                switch currentTab {
                case .overview:
                    ProjectOverview(
                        project: project,
                        resources: resources,
                        pending: pending,
                        deployments: activity.recentDeployments(
                            of: applications, namesEnvironments: namesEnvironments),
                        isLoadingDeployments: !activity.hasLoaded,
                        onOpen: { onOpen($0.route, nil) },
                        onOpenDeployment: { deployment in
                            open(deployment.application, at: .deployments)
                        },
                        onAction: { action, resource in onAction(action, resource.route) },
                        onEditEnvironment: canEdit ? { sheet = .editEnvironment($0) } : nil,
                        onAddEnvironment: canEdit ? onAddEnvironment : nil
                    )
                case .previews:
                    ProjectPreviews(
                        projectName: project.name,
                        groups: activity.previews(for: applications, namesEnvironments: namesEnvironments),
                        isLoading: !activity.hasLoaded,
                        gitHubURL: activity.gitHubURL(for:number:),
                        onOpen: { group, place in
                            open(group.application, at: .previews(place))
                        }
                    )
                case .variables:
                    SharedVariableList(model: page.variables, projectName: project.name)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
        .animation(.snappy, value: currentTab)
        .animation(.snappy, value: actionError)
        .animation(.snappy, value: activity.loadError)
        // The project's own name heads the screen below, so the toolbar only says what kind of screen this is.
        .navigationTitle("Project")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            DetailNavigation(title: "Project")
            // One group, so the two share a glass capsule. The button leaves with the page, since a resource
            // opened from here brings a toolbar of its own.
            ToolbarItemGroup(placement: .primaryAction) {
                if let onNewService {
                    Button("New Service", systemImage: "plus", action: onNewService)
                        .help("Create a service in \(project.name) from one of Coolify's templates (⇧⌘N)")
                }
                Menu {
                    Button("Edit Project…", systemImage: "pencil") {
                        sheet = .editProject
                    }
                    Button("New Environment…", systemImage: "plus") {
                        isAddingEnvironment = true
                    }
                    Divider()
                    Button("Reload", systemImage: "arrow.clockwise") {
                        reloads += 1
                        Task { await onReload() }
                    }
                } label: {
                    Label("Project Actions", systemImage: "ellipsis.circle")
                        .symbolEffect(.bounce, value: reloads)
                }
                .disabled(!canEdit)
                .help("Edit \(project.name), add an environment, or reload")
                .popover(isPresented: $isAddingEnvironment, arrowEdge: .bottom) {
                    NewPlacePopover(
                        kind: .environment,
                        note: "It starts empty in \(project.name). Resources are created in it from Coolify.",
                        takenNames: Set(project.environments.map(\.name)),
                        onAdd: onAddEnvironment
                    )
                }
            }
        }
        .sheet(item: $sheet) { sheet in
            editor(for: sheet)
        }
    }

    /// Opens an application somewhere other than its front, with the history this page already has.
    private func open(_ application: ResourceRoute, at place: ResourceEntry.Place) {
        onOpen(application, ResourceEntry(place: place, history: activity.history(for: application)))
    }

    @ViewBuilder
    private func editor(for sheet: ProjectSheet) -> some View {
        let names = Set(project.environments.map(\.name))
        switch sheet {
        case .editProject:
            PlaceEditor(
                title: "Edit Project",
                namePrompt: "Project name",
                name: project.name,
                description: project.description ?? "",
                tint: palette.project(project.id),
                canTint: palette.canEdit,
                onSave: onSaveProject,
                onTint: { palette.setProject($0, for: project.id) }
            )
        case .editEnvironment(let environment):
            PlaceEditor(
                title: "Edit Environment",
                namePrompt: "Environment name",
                name: environment.name,
                description: environment.description ?? "",
                takenNames: names.subtracting([environment.name]),
                tint: palette.environment(environment.uuid),
                canTint: palette.canEdit && environment.uuid != nil,
                onSave: { name, description in
                    try await onSaveEnvironment(environment, name, description)
                },
                onTint: { tint in
                    if let uuid = environment.uuid {
                        palette.setEnvironment(tint, for: uuid)
                    }
                }
            )
        }
    }
}

/// The views under the project header.
enum ProjectTab: Identifiable, Hashable {
    case overview
    case previews
    case variables

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .previews: "Previews"
        case .variables: "Variables"
        }
    }
}

/// The sheet open over the project page.
private enum ProjectSheet: Identifiable, Hashable {
    case editProject
    case editEnvironment(EnvironmentSummary)

    var id: Self { self }
}

#Preview {
    let now = Date.now
    let production = ResourcePlace(
        projectID: "website", projectName: "Website", environmentName: "production", environmentID: 1)
    let staging = ResourcePlace(
        projectID: "website", projectName: "Website", environmentName: "staging", environmentID: 2)
    NavigationStack {
        ProjectDetail(
            project: ProjectSummary(
                id: "website",
                name: "Website",
                description: "The marketing site, its API, and what they store.",
                createdAt: now.addingTimeInterval(-86_400 * 200),
                environments: [
                    EnvironmentSummary(id: 1, name: "production"),
                    EnvironmentSummary(id: 2, name: "staging"),
                ]
            ),
            resources: [
                ResourceSummary(
                    route: .application("web"),
                    name: "marketing-site",
                    status: "running:healthy",
                    subtitle: "hotify.example.com",
                    place: production
                ),
                ResourceSummary(
                    route: .database("pg"),
                    name: "postgres",
                    status: "running:healthy",
                    subtitle: "PostgreSQL",
                    place: production
                ),
                ResourceSummary(
                    route: .application("web-staging"),
                    name: "marketing-site",
                    status: "exited",
                    subtitle: "staging.hotify.example.com",
                    place: staging
                ),
            ],
            page: ProjectPageModel(
                activity: ProjectActivityModel(
                    histories: [
                        "web": [
                            DeploymentLine(
                                id: "2", status: "finished", commit: "abc1234", message: "fix: login redirect",
                                startedAt: now.addingTimeInterval(-3_600), finishedAt: now.addingTimeInterval(-3_528)),
                            DeploymentLine(
                                id: "p", status: "finished", commit: "def5678", message: "feat: pricing page",
                                pullRequest: 42, startedAt: now.addingTimeInterval(-7_200)),
                        ]
                    ],
                    hasLoaded: true
                ),
                variables: SharedVariablesModel(
                    sections: [
                        SharedVariableSection(
                            scope: .project("website"),
                            title: "Project",
                            lines: [VariableLine(id: "1", key: "API_URL", value: "https://api.example.com")]
                        )
                    ],
                    hasLoaded: true
                )),
            canEdit: true,
            onNewService: {}
        )
    }
    .frame(width: 640, height: 720)
    .environment(VariableLock(isRequired: true))
}

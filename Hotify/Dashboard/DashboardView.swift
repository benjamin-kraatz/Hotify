import SwiftUI

/// The middle column: one instance's projects, each with its resources by environment and actions on every row.
/// A project's head opens its page.
struct DashboardView: View {
    var instanceName: String
    var host: String
    var snapshot: DashboardSnapshot
    @Binding var selection: DetailRoute?
    var onRun: (ResourceAction, ResourceRoute) -> Void
    var onRefresh: () async -> Void
    /// Opens provisioning. `nil` hides the button, such as before the instance connects.
    var onNewService: (() -> Void)?

    @State private var query = ""
    @State private var filter = ResourceFilter()
    @State private var stopCandidate: ResourceSummary?
    @State private var refreshes = 0
    #if os(macOS)
    @FocusState private var isFiltering: Bool
    /// Whether the arrow keys go to the list.
    @FocusState private var isListFocused: Bool
    #endif

    /// What the typed text and the filter menu leave of the list. Each narrows what the other lets through.
    private var visible: [ResourceSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty || filter.isActive else { return snapshot.resources }
        return snapshot.resources.filter { resource in
            guard
                filter.includes(
                    resource, heat: resource.heat(pendingAction: snapshot.pendingAction(for: resource.route)))
            else { return false }
            return trimmed.isEmpty
                || resource.name.localizedStandardContains(trimmed)
                || resource.subtitle?.localizedStandardContains(trimmed) == true
                || resource.place?.projectName.localizedStandardContains(trimmed) == true
                || resource.place?.environmentName.localizedStandardContains(trimmed) == true
                || resource.containers.contains { $0.name.localizedStandardContains(trimmed) }
        }
    }

    /// Heat for the summary strip. A resource with an action or deployment in flight counts as warming.
    private var heats: [Heat] {
        snapshot.resources.map { $0.heat(pendingAction: snapshot.pendingAction(for: $0.route)) }
    }

    /// The list as it stands: a section per project. A project that holds nothing only shows while nothing
    /// narrows the list.
    private var sections: [ProjectSection] {
        let isNarrowed = filter.isActive || !query.trimmingCharacters(in: .whitespaces).isEmpty
        return ProjectSection.sections(of: visible, projects: snapshot.projects, includesEmpty: !isNarrowed)
    }

    private func heats(of section: ProjectSection) -> [Heat] {
        section.resources.map { $0.heat(pendingAction: snapshot.pendingAction(for: $0.route)) }
    }

    var body: some View {
        let sections = sections
        return list(sections)
            .overlay {
                overlay(isEmpty: sections.isEmpty)
            }
            #if os(macOS)
        // A search field in the toolbar would land over the detail column, far from the list it filters, and
        // take the trailing edge that column's own actions belong at. So the Mac filters from a bar above the
        // list.
        .safeAreaBar(edge: .top) {
            if snapshot.hasLoaded, !snapshot.resources.isEmpty {
                FilterField("Filter resources", text: $query, isFiltered: filter.isActive) {
                    ResourceFilterMenu(filter: $filter)
                }
                .focused($isFiltering)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .background {
            // Command-F puts the cursor in the filter, as it would in a search field.
            Button("Filter Resources") {
                isFiltering = true
            }
            .keyboardShortcut("f")
            .opacity(0)
            .accessibilityHidden(true)
        }
            #else
        .searchable(text: $query, prompt: "Filter resources")
        .refreshable {
            await onRefresh()
        }
            #endif
            .navigationTitle(instanceName)
            #if os(macOS)
        // The header already names the instance in the display face.
        .toolbar(removing: .title)
        #endif
        .toolbar {
            #if os(iOS)
            // The search bar has no room for the filter menu the Mac's field carries, so it gets a button.
            if snapshot.hasLoaded, !snapshot.resources.isEmpty {
                ToolbarItem {
                    Menu {
                        ResourceFilterMenu(filter: $filter)
                    } label: {
                        Label(
                            "Filters",
                            systemImage: filter.isActive
                                ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
                        )
                    }
                }
            }
            #endif
            if let onNewService {
                ToolbarItem {
                    Button("New Service", systemImage: "plus", action: onNewService)
                        .keyboardShortcut("n")
                        .help("Create a service from one of Coolify's templates")
                }
            }
            ToolbarItem {
                Button {
                    refreshes += 1
                    Task { await onRefresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .symbolEffect(.rotate, value: refreshes)
                }
                .keyboardShortcut("r")
                .help("Refresh now. Hotify also refreshes every 5 seconds.")
            }
        }
        .stopConfirmation(for: $stopCandidate) { resource in
            onRun(.stop, resource.route)
        }
        .sensoryFeedback(trigger: snapshot.pending) { old, new in
            new.count > old.count ? .impact(weight: .light) : nil
        }
        .animation(.snappy, value: sections.map(\.id))
        .animation(.snappy, value: visible.map(\.id))
        .animation(.snappy, value: snapshot.loadError)
        .animation(.snappy, value: snapshot.actionError)
    }

    /// The instance's own facts, above the projects: its name on the Mac, the team, how much runs, the servers.
    @ViewBuilder
    private var summary: some View {
        DashboardTitle(instanceName: instanceName, teamName: snapshot.teamName, version: snapshot.version)
        if !heats.isEmpty {
            HeatSummary(heats: heats)
        }
        ForEach(snapshot.servers) { server in
            ServerStatusLine(server: server)
        }
        if let loadError = snapshot.loadError {
            NoticeBanner(message: loadError)
        }
        if let actionError = snapshot.actionError {
            NoticeBanner(message: actionError)
        }
    }

    #if os(macOS)
    /// A panel per project. Not a `List`: its rows cannot sit inside a shared panel, and it animates a row's
    /// height poorly. The arrow keys step through the rows as they would in one.
    private func list(_ sections: [ProjectSection]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        summary
                    }
                    // In line with what the panels below hold, so every name in the column starts at one edge.
                    .padding(.horizontal, 4 + DashboardRowMetrics.inset)
                    .padding(.bottom, 4)

                    ForEach(sections) { section in
                        ProjectCard(section: section, heats: heats(of: section), selection: selection) { route in
                            isListFocused = true
                            selection = route
                        } row: { resource in
                            row(resource)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($isListFocused)
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                step(press.key == .downArrow ? 1 : -1, through: sections.flatMap(\.routes), scroll: proxy)
            }
        }
    }

    /// Moves the selection one row up or down, and keeps it in view.
    private func step(_ offset: Int, through routes: [DetailRoute], scroll proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !routes.isEmpty else { return .ignored }
        let current = selection.flatMap { routes.firstIndex(of: $0) }
        let next = current.map { min(max($0 + offset, 0), routes.count - 1) } ?? (offset > 0 ? 0 : routes.count - 1)
        selection = routes[next]
        proxy.scrollTo(routes[next])
        return .handled
    }
    #else
    /// A grouped section per project, headed by a row that opens it.
    private func list(_ sections: [ProjectSection]) -> some View {
        List(selection: $selection) {
            Section {
                summary
            }
            .listRowSeparator(.hidden)

            ForEach(sections) { section in
                Section {
                    if let projectID = section.projectID {
                        ProjectSectionHeader(section: section, heats: heats(of: section))
                            .tag(DetailRoute.project(projectID))
                    }
                    ForEach(section.environments) { environment in
                        if section.labelsEnvironments {
                            EnvironmentBadge(name: environment.name.isEmpty ? "Environment" : environment.name)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16))
                                .selectionDisabled()
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(environment.resources) { resource in
                            row(resource)
                                .tag(DetailRoute.resource(resource.route))
                        }
                    }
                } header: {
                    if section.projectID == nil {
                        Text(section.name)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        // The label of an environment is a short row of its own. The default would pad it out to a full one.
        .environment(\.defaultMinListRowHeight, 24)
    }
    #endif

    private func row(_ resource: ResourceSummary) -> some View {
        let pendingAction = snapshot.pendingAction(for: resource.route)
        let actions = ResourceAction.available(for: resource)
        return ResourceRow(resource: resource, pendingAction: pendingAction)
            .contextMenu {
                ResourceActionButtons(resource: resource, pendingAction: pendingAction) { action in
                    run(action, on: resource)
                }
                if let link = resource.link {
                    Divider()
                    Link(destination: link) {
                        Label("Open \(link.host() ?? link.absoluteString)", systemImage: "safari")
                    }
                }
            }
            #if os(iOS)
        .swipeActions(edge: .leading) {
            ForEach(actions.filter { $0 == .deploy || $0 == .restart }) { action in
                swipeButton(action, on: resource, isBusy: action.isBlocked(by: pendingAction))
            }
        }
        .swipeActions(edge: .trailing) {
            ForEach(actions.filter { $0 == .start || $0 == .stop || $0 == .cancelDeployment }) { action in
                swipeButton(action, on: resource, isBusy: action.isBlocked(by: pendingAction))
            }
        }
            #endif
    }

    #if os(iOS)
    private func swipeButton(_ action: ResourceAction, on resource: ResourceSummary, isBusy: Bool) -> some View {
        Button(action.title, systemImage: action.systemImage) {
            run(action, on: resource)
        }
        .tint(action.swipeTint)
        .disabled(isBusy)
    }
    #endif

    private func run(_ action: ResourceAction, on resource: ResourceSummary) {
        if action == .stop {
            stopCandidate = resource
        } else {
            onRun(action, resource.route)
        }
    }

    @ViewBuilder
    private func overlay(isEmpty: Bool) -> some View {
        if !snapshot.hasLoaded, snapshot.loadError == nil {
            VStack(spacing: 14) {
                FlameGlyph(heat: .warming, height: 44)
                Text("Connecting to \(host)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .transition(.opacity)
        } else if snapshot.hasLoaded, snapshot.resources.isEmpty, isEmpty {
            // A project that holds nothing still shows as a panel, so this is for a team without projects either.
            ContentUnavailableView {
                Label("Nothing deployed yet", systemImage: "flame")
            } description: {
                Text(
                    onNewService == nil
                        ? "This team has no applications, databases, or services. Create one in Coolify and it shows up here."
                        : "This team has no applications, databases, or services yet. Start one from Coolify's templates."
                )
            } actions: {
                if let onNewService {
                    Button("Browse Templates", systemImage: "plus", action: onNewService)
                        .glassButton(prominent: true)
                }
            }
        } else if visible.isEmpty, filter.isActive {
            // The filters may be why nothing shows, whatever was typed, so the way out is to clear them.
            ContentUnavailableView {
                Label("Nothing matches", systemImage: "line.3.horizontal.decrease")
            } description: {
                Text("No resource fits the filters that are on.")
            } actions: {
                Button("Clear Filters") {
                    filter = ResourceFilter()
                }
                .glassButton()
            }
        } else if !query.isEmpty, visible.isEmpty {
            ContentUnavailableView.search(text: query)
                // On the Mac the filter sits in the list underneath, and has to stay within reach to be changed.
                .allowsHitTesting(false)
        }
    }
}

#Preview {
    @Previewable @State var selection: DetailRoute?
    let website = ResourcePlace(
        projectID: "website", projectName: "Website", environmentName: "production", environmentID: 1)
    NavigationStack {
        DashboardView(
            instanceName: "Home lab",
            host: "coolify.example.com",
            snapshot: DashboardSnapshot(
                teamName: "Root Team",
                version: "4.3.23",
                servers: [ServerLine(id: "1", name: "localhost", isReachable: true)],
                resources: [
                    ResourceSummary(
                        route: .application("web"),
                        name: "marketing-site",
                        status: "running:healthy",
                        subtitle: "hotify.example.com",
                        place: website
                    ),
                    ResourceSummary(
                        route: .application("api"),
                        name: "api",
                        status: "exited",
                        subtitle: "example/api",
                        place: website,
                        isDeploying: true
                    ),
                    ResourceSummary(
                        route: .database("pg"),
                        name: "postgres",
                        status: "running:healthy",
                        subtitle: "PostgreSQL",
                        place: website
                    ),
                    ResourceSummary(
                        route: .service("kibana"),
                        name: "elasticsearch-with-kibana",
                        status: "exited",
                        subtitle: "3 containers",
                        containers: [
                            ContainerSummary(id: 1, name: "kibana", status: "exited"),
                            ContainerSummary(id: 2, name: "elasticsearch", status: "exited"),
                            ContainerSummary(id: 3, name: "token-generator", status: "exited"),
                        ],
                        place: ResourcePlace(
                            projectID: "observability", projectName: "Observability", environmentName: "staging",
                            environmentID: 3)
                    ),
                ],
                pending: [.database("pg"): .restart],
                hasLoaded: true
            ),
            selection: $selection,
            onRun: { _, _ in },
            onRefresh: {}
        )
    }
}

#Preview("Connecting") {
    NavigationStack {
        DashboardView(
            instanceName: "Home lab",
            host: "coolify.example.com",
            snapshot: DashboardSnapshot(isLoading: true),
            selection: .constant(nil),
            onRun: { _, _ in },
            onRefresh: {}
        )
    }
}

#if os(iOS)
extension ResourceAction {
    /// Ember for actions that bring something up, amber for a bounce, grey for ones that take it down.
    fileprivate var swipeTint: Color {
        switch self {
        case .start, .deploy: .ember
        case .restart: .glow
        case .stop, .cancelDeployment: .gray
        }
    }
}
#endif

import SwiftUI

/// The middle column: one instance's resources, grouped by project and environment, with actions on each row.
struct DashboardView: View {
    var instanceName: String
    var host: String
    var snapshot: DashboardSnapshot
    @Binding var selection: ResourceRoute?
    var onRun: (ResourceAction, ResourceRoute) -> Void
    var onRefresh: () async -> Void
    /// Opens provisioning. `nil` hides the button, such as before the instance connects.
    var onNewService: (() -> Void)?

    @State private var query = ""
    @State private var stopCandidate: ResourceSummary?
    @State private var refreshes = 0

    private var visible: [ResourceSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return snapshot.resources }
        return snapshot.resources.filter { resource in
            resource.name.localizedStandardContains(trimmed)
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

    var body: some View {
        List(selection: $selection) {
            Section {
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
            .listRowSeparator(.hidden)

            ForEach(ResourceGroup.grouping(visible)) { group in
                Section {
                    ForEach(group.resources) { resource in
                        row(resource)
                    }
                } header: {
                    GroupHeader(place: group.place)
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #else
        .listStyle(.insetGrouped)
        #endif
        .overlay {
            overlay
        }
        #if os(macOS)
        // The default placement parks the field over the detail column, far from the list it filters.
        .searchable(text: $query, placement: .sidebar, prompt: "Filter resources")
        #else
        .searchable(text: $query, prompt: "Filter resources")
        #endif
        .refreshable {
            await onRefresh()
        }
        .navigationTitle(instanceName)
        #if os(macOS)
        // The header already names the instance in the display face.
        .toolbar(removing: .title)
        #endif
        .toolbar {
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
        .animation(.snappy, value: visible.map(\.id))
        .animation(.snappy, value: snapshot.loadError)
        .animation(.snappy, value: snapshot.actionError)
    }

    private func row(_ resource: ResourceSummary) -> some View {
        let pendingAction = snapshot.pendingAction(for: resource.route)
        let actions = ResourceAction.available(for: resource)
        return ResourceRow(resource: resource, pendingAction: pendingAction)
            .tag(resource.route)
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
    private var overlay: some View {
        if !snapshot.hasLoaded, snapshot.loadError == nil {
            VStack(spacing: 14) {
                FlameGlyph(heat: .warming, height: 44)
                Text("Connecting to \(host)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .transition(.opacity)
        } else if snapshot.hasLoaded, snapshot.resources.isEmpty {
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
        } else if !query.isEmpty, visible.isEmpty {
            ContentUnavailableView.search(text: query)
        }
    }
}

#Preview {
    @Previewable @State var selection: ResourceRoute?
    let website = ResourcePlace(projectName: "Website", environmentName: "production", environmentID: 1)
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
                        place: ResourcePlace(projectName: "Observability", environmentName: "staging", environmentID: 3)
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

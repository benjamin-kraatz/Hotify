import SwiftUI

/// The middle column: one instance's applications, databases, and services, with actions on each row.
struct DashboardView: View {
    var instanceName: String
    var host: String
    var snapshot: DashboardSnapshot
    @Binding var selection: ResourceRoute?
    var onRun: (ResourceAction, ResourceRoute) -> Void
    var onRefresh: () async -> Void

    @State private var query = ""
    @State private var stopCandidate: ResourceSummary?
    @State private var refreshes = 0

    private var visible: [ResourceSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return snapshot.resources }
        return snapshot.resources.filter { resource in
            resource.name.localizedStandardContains(trimmed)
                || resource.subtitle?.localizedStandardContains(trimmed) == true
                || resource.containers.contains { $0.name.localizedStandardContains(trimmed) }
        }
    }

    /// Heat for the summary strip. A resource with an action in flight counts as warming.
    private var heats: [Heat] {
        snapshot.resources.map { resource in
            snapshot.pendingAction(for: resource.route) == nil ? resource.heat : .warming
        }
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

            ForEach(ResourceKind.allCases, id: \.self) { kind in
                let rows = visible.filter { $0.kind == kind }
                if !rows.isEmpty {
                    Section(kind.pluralTitle) {
                        ForEach(rows) { resource in
                            row(resource)
                        }
                    }
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
        let heat = resource.heat
        return ResourceRow(resource: resource, pendingAction: pendingAction)
            .tag(resource.route)
            .contextMenu {
                ResourceActionButtons(heat: heat, isBusy: pendingAction != nil) { action in
                    if action == .stop {
                        stopCandidate = resource
                    } else {
                        onRun(action, resource.route)
                    }
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
            if heat != .cold {
                Button("Restart", systemImage: ResourceAction.restart.systemImage) {
                    onRun(.restart, resource.route)
                }
                .tint(.glow)
                .disabled(pendingAction != nil)
            }
        }
        .swipeActions(edge: .trailing) {
            if heat == .cold || heat == .unknown {
                Button("Start", systemImage: ResourceAction.start.systemImage) {
                    onRun(.start, resource.route)
                }
                .tint(.ember)
                .disabled(pendingAction != nil)
            } else {
                Button("Stop", systemImage: ResourceAction.stop.systemImage) {
                    stopCandidate = resource
                }
                .tint(.gray)
                .disabled(pendingAction != nil)
            }
        }
            #endif
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
                    "This team has no applications, databases, or services. Create one in Coolify and it shows up here."
                )
            }
        } else if !query.isEmpty, visible.isEmpty {
            ContentUnavailableView.search(text: query)
        }
    }
}

#Preview {
    @Previewable @State var selection: ResourceRoute?
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
                        subtitle: "hotify.example.com"
                    ),
                    ResourceSummary(route: .database("pg"), name: "postgres", status: "running:healthy"),
                    ResourceSummary(
                        route: .service("kibana"),
                        name: "elasticsearch-with-kibana",
                        status: "exited",
                        subtitle: "3 containers",
                        containers: [
                            ContainerSummary(id: 1, name: "kibana", status: "exited"),
                            ContainerSummary(id: 2, name: "elasticsearch", status: "exited"),
                            ContainerSummary(id: 3, name: "token-generator", status: "exited"),
                        ]
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

import CoolifyAPI
import SwiftUI

/// The window: instances, then the selected instance's resources, then the open resource.
struct ContentView: View {
    @SwiftUI.Environment(InstanceStore.self) private var store
    @State private var dashboard = DashboardModel()
    @State private var dashboards: [CoolifyInstance.ID: DashboardModel] = [:]
    @State private var client: CoolifyClient?
    @State private var boundID: CoolifyInstance.ID?
    @State private var isAdding = false
    @State private var editing: CoolifyInstance?
    @State private var selectedResource: ResourceRoute?

    var body: some View {
        ZStack {
            if store.instances.isEmpty {
                WelcomeView { isAdding = true }
                    .transition(.opacity)
            } else {
                splitView
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: store.instances.isEmpty)
        .onAppear {
            store.seedFromEnvironment()
            rebind()
        }
        .onChange(of: store.selectedID) { _, _ in
            selectedResource = nil
            rebind()
        }
        .sheet(isPresented: $isAdding) {
            formSheet(
                InstanceForm { name, url, token in
                    let _ = try store.add(name: name, baseURL: url, token: token)
                }
            )
        }
        .sheet(item: $editing) { instance in
            formSheet(
                InstanceForm(
                    title: "Edit Instance",
                    confirmTitle: "Save",
                    name: instance.name,
                    baseURL: instance.baseURL.absoluteString,
                    token: TokenStore.load(for: instance.id) ?? ""
                ) { name, url, token in
                    let connectionChanged = try store.update(
                        id: instance.id,
                        name: name,
                        baseURL: url,
                        token: token
                    )
                    guard store.selectedID == instance.id, connectionChanged else { return }
                    selectedResource = nil
                    rebind()
                }
            )
        }
    }

    private var splitView: some View {
        NavigationSplitView {
            InstanceSidebar(isAdding: $isAdding, editing: $editing, heat: heat(for:))
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } content: {
            dashboardColumn
                .navigationSplitViewColumnWidth(min: 320, ideal: 390, max: 560)
        } detail: {
            detailColumn
        }
    }

    @ViewBuilder
    private var dashboardColumn: some View {
        if let instance = store.selected {
            if boundID == instance.id, client == nil {
                ContentUnavailableView {
                    Label("No API token", systemImage: "key.slash")
                } description: {
                    Text(
                        "Hotify can't find a token for \(instance.name) in the Keychain. Edit the instance and paste it again."
                    )
                } actions: {
                    Button("Edit \(instance.name)") {
                        editing = instance
                    }
                    .glassButton(prominent: true)
                }
            } else {
                DashboardView(
                    instanceName: instance.name,
                    host: instance.displayHost,
                    snapshot: dashboard.snapshot,
                    selection: $selectedResource,
                    onRun: run,
                    onRefresh: { await dashboard.refresh() }
                )
            }
        } else {
            ContentUnavailableView(
                "Pick an instance",
                systemImage: "sidebar.left",
                description: Text("Choose a Coolify instance in the sidebar.")
            )
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        let snapshot = dashboard.snapshot
        if let route = selectedResource, let resource = snapshot.resource(route) {
            ResourceDetailScreen(
                client: client,
                resource: resource,
                pendingAction: snapshot.pendingAction(for: route),
                onAction: { action in run(action, route) }
            )
            .id(route)
        } else {
            ContentUnavailableView {
                Label {
                    Text(selectedResource == nil ? "Nothing open" : "This resource is gone")
                } icon: {
                    FlameGlyph(heat: .cold, height: 48)
                }
            } description: {
                Text(
                    selectedResource == nil
                        ? "Pick an application, database, or service to see its logs and deployments."
                        : "Coolify no longer lists it. It may have been deleted."
                )
            }
        }
    }

    private func formSheet<Content: View>(_ content: Content) -> some View {
        content
            .presentationDetents([.fraction(0.37), .large])
            .presentationDragIndicator(.hidden)
            .presentationContentInteraction(.automatic)
    }

    private func heat(for instance: CoolifyInstance) -> Heat {
        guard instance.id == boundID, client != nil else { return .unknown }
        if dashboard.loadError != nil {
            return .troubled
        }
        return dashboard.lastUpdated == nil ? .warming : .lit
    }

    private func run(_ action: ResourceAction, _ route: ResourceRoute) {
        Task { await dashboard.perform(action, route: route) }
    }

    private func rebind() {
        dashboard.stop()
        let ids = Set(store.instances.map(\.id))
        dashboards = dashboards.filter { ids.contains($0.key) }
        guard let selected = store.selected else {
            client = nil
            boundID = nil
            return
        }

        if let cachedDashboard = dashboards[selected.id] {
            dashboard = cachedDashboard
        } else {
            let newDashboard = DashboardModel()
            dashboards[selected.id] = newDashboard
            dashboard = newDashboard
        }
        // Read the Keychain once per switch rather than on every render.
        client = store.client(for: selected)
        boundID = selected.id
        dashboard.bind(client)
    }
}

#Preview {
    ContentView()
        .environment(InstanceStore(instances: []))
}

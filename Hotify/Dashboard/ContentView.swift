import CoolifyAPI
import SwiftUI

/// The window: instances, then the selected instance's resources, then the open resource.
struct ContentView: View {
    @SwiftUI.Environment(MenuBarModel.self) private var menuBar
    @SwiftUI.Environment(InstanceStore.self) private var store
    @SwiftUI.Environment(\.scenePhase) private var scenePhase
    @State private var boundToken: String?
    @State private var dashboard = DashboardModel()
    @State private var dashboards: [CoolifyInstance.ID: DashboardModel] = [:]
    @State private var client: CoolifyClient?
    @State private var boundID: CoolifyInstance.ID?
    @State private var isAdding = false
    @State private var editing: CoolifyInstance?
    @State private var selectedResource: ResourceRoute?
    @State private var catalog = TemplateCatalog()
    @State private var isProvisioning = false

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
        .safeAreaInset(edge: .top) {
            if let message = store.syncError {
                NoticeBanner(message: message).padding()
            }
        }
        .animation(.smooth, value: store.instances.isEmpty)
        .onAppear {
            store.seedFromEnvironment()
            rebind()
            followMenuBarSelection()
        }
        .onChange(of: menuBar.navigation) { _, _ in followMenuBarSelection() }
        .onChange(of: store.selectedID) { _, _ in
            isProvisioning = false
            selectedResource = nil
            rebind()
            if menuBar.navigation?.instanceID == store.selectedID { selectedResource = menuBar.navigation?.route }
        }
        .onChange(of: store.selected?.baseURL) { _, _ in
            resetConnection()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            store.refreshSync()
            // Keychain sync has no public arrival notification. Check while this window is active.
            while !Task.isCancelled {
                let token = store.selected.flatMap { TokenStore.load(for: $0.id) }
                if token != boundToken { resetConnection() }
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
        .sheet(isPresented: $isAdding) {
            formSheet(
                InstanceForm { name, url, token in
                    let _ = try store.add(name: name, baseURL: url, token: token)
                }
            )
        }
        .sheet(isPresented: $isProvisioning) {
            ProvisioningSheet(client: client, instanceID: store.selectedID, catalog: catalog) { route in
                isProvisioning = false
                guard let route else { return }
                Task {
                    // The dashboard learns of the new service on its next poll. Ask now, so it opens at once.
                    await dashboard.refresh()
                    selectedResource = route
                }
            }
            .id(store.selectedID)
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
                    resetConnection()
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
                        "The token for \(instance.name) hasn't arrived. Enable iCloud Keychain on both devices, or edit the instance to paste it. Hotify will connect when the token arrives."
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
                    onRefresh: { await dashboard.refresh() },
                    onNewService: client == nil ? nil : { isProvisioning = true }
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
                actionError: snapshot.actionError,
                onAction: { action in run(action, route) }
            )
            .id(DetailIdentity(instanceID: store.selectedID, route: route))
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

    private func followMenuBarSelection() {
        guard let request = menuBar.navigation, store.instances.contains(where: { $0.id == request.instanceID }) else {
            return
        }
        store.selectedID = request.instanceID
        selectedResource = request.route
    }

    private func resetConnection() {
        selectedResource = nil
        if let id = store.selectedID { dashboards.removeValue(forKey: id) }
        rebind()
        if menuBar.navigation?.instanceID == store.selectedID { selectedResource = menuBar.navigation?.route }
    }

    private func rebind() {
        dashboard.stop()
        let ids = Set(store.instances.map(\.id))
        dashboards = dashboards.filter { ids.contains($0.key) }
        guard let selected = store.selected else {
            client = nil
            boundID = nil
            boundToken = nil
            dashboard = DashboardModel()
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
        boundToken = TokenStore.load(for: selected.id)
        client = store.client(for: selected)
        boundID = selected.id
        dashboard.bind(client)
    }
}

#Preview {
    ContentView()
        .environment(InstanceStore(instances: []))
        .environment(MenuBarModel(preview: true))
        .environment(VariableLock(isRequired: true))
}

/// Keeps detail tasks isolated even when two instances contain the same resource UUID.
private struct DetailIdentity: Hashable {
    var instanceID: UUID?
    var route: ResourceRoute
}

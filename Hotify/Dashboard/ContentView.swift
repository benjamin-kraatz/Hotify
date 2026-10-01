import CoolifyAPI
import SwiftUI

/// The window: instances, then the selected instance's resources, then the open resource or project.
struct ContentView: View {
    @SwiftUI.Environment(MenuBarModel.self) private var menuBar
    @SwiftUI.Environment(InstanceStore.self) private var store
    @SwiftUI.Environment(\.scenePhase) private var scenePhase
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var boundToken: String?
    @State private var dashboard = DashboardModel()
    @State private var dashboards: [CoolifyInstance.ID: DashboardModel] = [:]
    @State private var client: CoolifyClient?
    @State private var boundID: CoolifyInstance.ID?
    @State private var isAdding = false
    @State private var editing: CoolifyInstance?
    @State private var selection: DetailRoute?
    /// Set while the selected resource is one the project page opened: where it opens, and the project to go back to.
    @State private var entry: EntryRequest?
    /// The project page's tab and loaded data. Kept here so the page is as it was left after a visit to a resource.
    @State private var projectPage = ProjectPageModel()
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
        .onOpenURL { url in
            // A widget's link goes through the menu bar's request, so a switch of instance reopens it the same way.
            guard let link = ResourceLink(url: url) else { return }
            menuBar.navigation = MenuBarNavigation(instanceID: link.instanceID, route: link.route)
        }
        .onChange(of: store.selectedID) { _, _ in
            isProvisioning = false
            selection = nil
            rebind()
            followMenuBarRoute()
        }
        .onChange(of: selection) { _, selection in
            // An entry is for one visit. Picking anything else, the resource's own row included, starts over.
            if selection != entry.map({ .resource($0.route) }) {
                entry = nil
            }
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
                    selection = .resource(route)
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
                    selection: $selection,
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
        // A stack only so that a resource the project page opens can slide in over it, and slide back out.
        // Picking from the list changes the selection outside an animation, and swaps the screens at once.
        ZStack {
            switch selection {
            case .resource(let route):
                resourceScreen(route, from: entry?.route == route ? entry : nil)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .project(let id):
                if let project = snapshot.project(id) {
                    projectScreen(project)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                } else {
                    nothingOpen(
                        "This project is gone", detail: "Coolify no longer lists it. It may have been deleted.")
                }
            case nil:
                nothingOpen(
                    "Nothing open",
                    detail:
                        "Pick an application, database, or service to see its logs and deployments, or a project's name to see everything in it."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func projectScreen(_ project: ProjectSummary) -> some View {
        let snapshot = dashboard.snapshot
        let identity = DetailIdentity(instanceID: store.selectedID, route: .project(project.id))
        return ProjectDetailScreen(
            client: client,
            page: projectPage,
            key: identity,
            project: project,
            resources: snapshot.resources(inProject: project.id),
            pending: snapshot.pending,
            actionError: snapshot.actionError,
            onOpen: { route, entry in
                open(route, entry: entry, from: project)
            },
            onAction: run,
            onChanged: { await dashboard.reloadProjects() }
        )
        .id(identity)
    }

    /// `request` is set when the project page opened the resource. It says where the resource opens, and makes
    /// the toolbar's back button lead to the project.
    @ViewBuilder
    private func resourceScreen(_ route: ResourceRoute, from request: EntryRequest?) -> some View {
        let snapshot = dashboard.snapshot
        if let resource = snapshot.resource(route) {
            ResourceDetailScreen(
                client: client,
                resource: resource,
                pendingAction: snapshot.pendingAction(for: route),
                actionError: snapshot.actionError,
                entry: request?.entry,
                back: request.map { request in
                    DetailBack(title: snapshot.project(request.projectID)?.name ?? request.projectName) {
                        show(.project(request.projectID))
                    }
                },
                onOpenProject: resource.place.map { place in
                    { show(.project(place.projectID)) }
                },
                onAction: { action in run(action, route) }
            )
            .id(DetailIdentity(instanceID: store.selectedID, route: .resource(route)))
        } else {
            nothingOpen("This resource is gone", detail: "Coolify no longer lists it. It may have been deleted.")
        }
    }

    private func nothingOpen(_ title: String, detail: String) -> some View {
        ContentUnavailableView {
            Label {
                Text(title)
            } icon: {
                FlameGlyph(heat: .cold, height: 48)
            }
        } description: {
            Text(detail)
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

    /// Opens a resource from the project page, at the place the page pointed to.
    private func open(_ route: ResourceRoute, entry: ResourceEntry?, from project: ProjectSummary) {
        self.entry = EntryRequest(route: route, entry: entry, projectID: project.id, projectName: project.name)
        show(.resource(route))
    }

    /// Moves between a project and one of its resources, sliding one screen over the other.
    private func show(_ route: DetailRoute) {
        withAnimation(reduceMotion ? nil : .snappy) {
            selection = route
        }
    }

    private func followMenuBarSelection() {
        guard let request = menuBar.navigation, store.instances.contains(where: { $0.id == request.instanceID }) else {
            return
        }
        store.selectedID = request.instanceID
        selection = .resource(request.route)
    }

    /// Reopens the resource the menu bar asked for, after a switch of instance cleared the selection.
    private func followMenuBarRoute() {
        if let request = menuBar.navigation, request.instanceID == store.selectedID {
            selection = .resource(request.route)
        }
    }

    private func resetConnection() {
        selection = nil
        if let id = store.selectedID { dashboards.removeValue(forKey: id) }
        rebind()
        followMenuBarRoute()
    }

    private func rebind() {
        dashboard.stop()
        // What the page loaded came through the last connection.
        projectPage = ProjectPageModel()
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
    var route: DetailRoute
}

/// A resource the project page opened: where in it, and the project to go back to. No entry opens it at its front.
private struct EntryRequest: Hashable {
    var route: ResourceRoute
    var entry: ResourceEntry?
    var projectID: String
    var projectName: String
}

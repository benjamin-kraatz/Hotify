import CoolifyAPI
import SwiftUI

struct ContentView: View {
    @State private var store = InstanceStore()
    @State private var dashboard = DashboardModel()
    @State private var isAdding = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedID) {
                ForEach(store.instances) { instance in
                    VStack(alignment: .leading) {
                        Text(instance.name)
                        Text(instance.baseURL.absoluteString)
                    }
                    .tag(instance.id)
                    .contextMenu {
                        Button("Remove", role: .destructive) {
                            store.remove(instance)
                        }
                    }
                }
            }
            .navigationTitle("Instances")
            .toolbar {
                Button("Add") { isAdding = true }
            }
        } detail: {
            NavigationStack(path: $path) {
                Group {
                    if store.selected == nil {
                        Text("No instance")
                    } else if selectedClient == nil {
                        Text("No token for this instance")
                    } else {
                        resourceList
                    }
                }
                .navigationTitle(dashboard.teamName.isEmpty ? "Hotify" : dashboard.teamName)
                .toolbar {
                    if path.isEmpty, !dashboard.version.isEmpty {
                        Text(dashboard.version)
                    }
                    if path.isEmpty {
                        Button("Refresh") {
                            Task { await dashboard.refresh() }
                        }
                    }
                }
                .navigationDestination(for: ResourceRoute.self) { route in
                    if let selectedClient {
                        ResourceDetailScreen(
                            client: selectedClient,
                            route: route,
                            title: title(for: route),
                            status: status(for: route),
                            isBusy: dashboard.busyTargets.contains(route.busyTarget),
                            onStart: { run(.start, route: route) },
                            onRestart: { run(.restart, route: route) },
                            onStop: { run(.stop, route: route) }
                        )
                    }
                }
            }
        }
        .task {
            store.seedFromEnvironment()
            rebind()
        }
        .onChange(of: store.selectedID) { _, _ in
            path = NavigationPath()
            rebind()
        }
        .sheet(isPresented: $isAdding) {
            AddInstanceForm { name, url, token in
                let _ = try store.add(name: name, baseURL: url, token: token)
            }
            .presentationDetents([.fraction(0.37), .large])
            .presentationDragIndicator(.hidden)
            //            .interactiveDismissDisabled()
            //            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .presentationContentInteraction(.automatic)
        }
    }

    private var resourceListsAreEmpty: Bool {
        dashboard.applications.isEmpty && dashboard.databases.isEmpty && dashboard.services.isEmpty
    }

    private var resourceList: some View {
        List {
            if let loadError = dashboard.loadError {
                Text(loadError)
            }
            if let actionError = dashboard.actionError {
                Text(actionError)
            }
            if let server = dashboard.servers.first {
                Text("\(server.name) \(server.isReachable == true ? "reachable" : "unreachable")")
            }
            if dashboard.isLoading, resourceListsAreEmpty {
                Text("Loading")
            } else if resourceListsAreEmpty, dashboard.loadError == nil {
                Text("No resources")
            }
            if !dashboard.applications.isEmpty {
                Section("Applications") {
                    ForEach(dashboard.applications, id: \.uuid) { application in
                        NavigationLink(value: ResourceRoute.application(application.uuid)) {
                            ResourceRow(
                                title: application.name.isEmpty ? application.uuid : application.name,
                                status: application.status ?? "unknown",
                                detailLines: applicationLines(application),
                                isBusy: dashboard.busyTargets.contains(.application(application.uuid)),
                                onStart: { run(.start, on: application) },
                                onRestart: { run(.restart, on: application) },
                                onStop: { run(.stop, on: application) }
                            )
                        }
                    }
                }
            }
            if !dashboard.databases.isEmpty {
                Section("Databases") {
                    ForEach(dashboard.databases) { database in
                        NavigationLink(value: ResourceRoute.database(database.uuid)) {
                            ResourceRow(
                                title: databaseTitle(database),
                                status: database.status ?? "unknown",
                                detailLines: [],
                                isBusy: dashboard.busyTargets.contains(.database(database.uuid)),
                                onStart: { run(.start, on: database) },
                                onRestart: { run(.restart, on: database) },
                                onStop: { run(.stop, on: database) }
                            )
                        }
                    }
                }
            }
            if !dashboard.services.isEmpty {
                Section("Services") {
                    ForEach(dashboard.services) { service in
                        NavigationLink(value: ResourceRoute.service(service.uuid)) {
                            ResourceRow(
                                title: service.serviceType ?? service.name,
                                status: service.status ?? "unknown",
                                detailLines: (service.applications ?? []).map { container in
                                    "\(container.humanName ?? container.name) \(container.status ?? "unknown")"
                                },
                                isBusy: dashboard.busyTargets.contains(.service(service.id)),
                                onStart: { run(.start, on: service) },
                                onRestart: { run(.restart, on: service) },
                                onStop: { run(.stop, on: service) }
                            )
                        }
                    }
                }
            }
        }
    }

    private func applicationLines(_ application: Application) -> [String] {
        guard let fqdn = application.fqdn, !fqdn.isEmpty else { return [] }
        return [fqdn]
    }

    private func databaseTitle(_ database: Database) -> String {
        if let name = database.name, !name.isEmpty {
            return name
        }
        return database.uuid
    }

    private func run(_ action: ResourceAction, on application: Application) {
        Task { await dashboard.perform(action, on: application) }
    }

    private func run(_ action: ResourceAction, on database: Database) {
        Task { await dashboard.perform(action, on: database) }
    }

    private func run(_ action: ResourceAction, on service: Service) {
        Task { await dashboard.perform(action, on: service) }
    }

    private var selectedClient: CoolifyClient? {
        store.selected.flatMap { store.client(for: $0) }
    }

    private func title(for route: ResourceRoute) -> String {
        switch route {
        case .application(let uuid):
            guard let application = dashboard.applications.first(where: { $0.uuid == uuid }) else {
                return uuid
            }
            return application.name.isEmpty ? application.uuid : application.name
        case .database(let uuid):
            guard let database = dashboard.databases.first(where: { $0.uuid == uuid }) else {
                return uuid
            }
            return databaseTitle(database)
        case .service(let uuid):
            guard let service = dashboard.services.first(where: { $0.uuid == uuid }) else {
                return uuid
            }
            return service.serviceType ?? service.name
        }
    }

    private func status(for route: ResourceRoute) -> String {
        switch route {
        case .application(let uuid):
            dashboard.applications.first { $0.uuid == uuid }?.status ?? "unknown"
        case .database(let uuid):
            dashboard.databases.first { $0.uuid == uuid }?.status ?? "unknown"
        case .service(let uuid):
            dashboard.services.first { $0.uuid == uuid }?.status ?? "unknown"
        }
    }

    private func run(_ action: ResourceAction, route: ResourceRoute) {
        switch route {
        case .application(let uuid):
            guard let application = dashboard.applications.first(where: { $0.uuid == uuid }) else { return }
            run(action, on: application)
        case .database(let uuid):
            guard let database = dashboard.databases.first(where: { $0.uuid == uuid }) else { return }
            run(action, on: database)
        case .service(let uuid):
            guard let service = dashboard.services.first(where: { $0.uuid == uuid }) else { return }
            run(action, on: service)
        }
    }

    private func rebind() {
        guard let selected = store.selected else {
            dashboard.stop()
            return
        }
        dashboard.bind(store.client(for: selected))
    }
}

#Preview {
    ContentView()
}

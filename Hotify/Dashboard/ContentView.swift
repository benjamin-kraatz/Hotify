import CoolifyAPI
import SwiftUI

struct ContentView: View {
    @State private var store = InstanceStore()
    @State private var dashboard = DashboardModel()
    @State private var isAdding = false

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
            Group {
                if store.selected == nil {
                    Text("No instance")
                } else if store.selected.flatMap({ store.client(for: $0) }) == nil {
                    Text("No token for this instance")
                } else {
                    serviceList
                }
            }
            .navigationTitle(dashboard.teamName.isEmpty ? "Hotify" : dashboard.teamName)
            .toolbar {
                if !dashboard.version.isEmpty {
                    Text(dashboard.version)
                }
                Button("Refresh") {
                    Task { await dashboard.refresh() }
                }
            }
        }
        .task {
            store.seedFromEnvironment()
            rebind()
        }
        .onChange(of: store.selectedID) { _, _ in
            rebind()
        }
        .sheet(isPresented: $isAdding) {
            AddInstanceForm { name, url, token in
                try store.add(name: name, baseURL: url, token: token)
            }
        }
    }

    private var serviceList: some View {
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
            ForEach(dashboard.services) { service in
                ServiceRow(
                    title: service.serviceType ?? service.name,
                    status: service.status ?? "unknown",
                    containerLines: (service.applications ?? []).map { container in
                        "\(container.humanName ?? container.name) \(container.status ?? "unknown")"
                    },
                    isBusy: dashboard.busyServiceIDs.contains(service.id),
                    onStart: { run(.start, on: service) },
                    onRestart: { run(.restart, on: service) },
                    onStop: { run(.stop, on: service) }
                )
            }
        }
    }

    private func run(_ action: ServiceAction, on service: Service) {
        Task { await dashboard.perform(action, on: service) }
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

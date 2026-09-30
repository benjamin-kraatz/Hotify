import CoolifyAPI
import SwiftUI

/// Chooses an instance and one of its resources without changing the main window's selection.
///
/// Two plain rows with no container of their own, so a form section and a card can both hold them.
struct ResourcePicker: View {
    @SwiftUI.Environment(InstanceStore.self) private var store
    @Binding var endpoint: ResourceEndpoint?
    @State private var instanceID: UUID?
    @State private var resources: [ResourceSummary] = []
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Instance") {
                Picker(
                    "Instance",
                    selection: Binding(
                        get: { instanceID },
                        set: {
                            instanceID = $0
                            endpoint = nil
                        })
                ) {
                    Text("Choose…").tag(Optional<UUID>.none)
                    ForEach(store.instances) { instance in Text(instance.name).tag(Optional(instance.id)) }
                }
            }
            row("Resource") {
                if loading {
                    ProgressView()
                        .controlSize(.small)
                }
                Picker(
                    "Resource",
                    selection: Binding(
                        get: { endpoint?.resource.route },
                        set: { route in
                            guard let instance = store.instances.first(where: { $0.id == instanceID }),
                                let resource = resources.first(where: { $0.route == route })
                            else {
                                endpoint = nil
                                return
                            }
                            endpoint = ResourceEndpoint(
                                instanceID: instance.id, instanceName: instance.name, resource: resource)
                        })
                ) {
                    Text("Choose…").tag(Optional<ResourceRoute>.none)
                    ForEach(resources) { resource in
                        Label(resource.name, systemImage: resource.kind.systemImage).tag(Optional(resource.route))
                    }
                }
                .disabled(loading || instanceID == nil)
            }
            if let error {
                NoticeBanner(message: error)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .animation(.snappy, value: error)
        .onAppear { instanceID = endpoint?.instanceID }
        .onChange(of: endpoint?.instanceID) { _, id in if let id { instanceID = id } }
        .task(id: instanceID) { await loadResources() }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            content()
        }
    }

    private func loadResources() async {
        resources = []
        error = nil
        guard let instance = store.instances.first(where: { $0.id == instanceID }) else { return }
        guard let client = store.client(for: instance) else {
            error = "No API token for this instance."
            return
        }
        loading = true
        defer { loading = false }
        do {
            async let apps = client.applications()
            async let databases = client.databases()
            async let services = client.services()
            let loaded = try await (apps, databases, services)
            try Task.checkCancellation()
            resources =
                loaded.0.map { ResourceSummary(application: $0) } + loaded.1.map { ResourceSummary(database: $0) }
                + loaded.2.map { ResourceSummary(service: $0) }
            resources.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch is CancellationError { return } catch {
            self.error = (error as? CoolifyError)?.message ?? error.localizedDescription
        }
    }
}

#Preview {
    ResourcePicker(endpoint: .constant(nil))
        .padding(14)
        .well()
        .padding()
        .frame(width: 360)
        .environment(InstanceStore(instances: []))
}

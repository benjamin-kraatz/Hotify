import CoolifyAPI
import SwiftUI

/// Migrates a resource to another server. Coolify stops it, and it has to be deployed again.
struct MigrateSheet: View {
    var resourceName: String
    var route: ResourceRoute
    var client: CoolifyClient?

    @Bindable var catalog: DestinationCatalog
    var heat: Heat = .unknown
    var origin: String?
    @State private var migrateVolumes = true
    @State private var confirm = false
    @State private var isSaving = false
    @State private var failure: String?
    @SwiftUI.Environment(\.dismiss) private var dismiss

    private var destinationUUID: String? {
        let uuid = catalog.destinationUUID ?? ""
        return uuid.isEmpty ? nil : uuid
    }

    private var canMigrate: Bool { destinationUUID != nil && !isSaving && !catalog.isLoadingDestinations }

    var body: some View {
        PlacementChrome(
            title: "Migrate", actionTitle: "Migrate", canAct: canMigrate, isBusy: isSaving, failure: failure,
            journey: catalog.destinationJourney(resourceName: resourceName, heat: heat, origin: origin),
            onAct: { confirm = true }
        ) {
            DestinationChoice(catalog: catalog)

            Section {
                Toggle(isOn: $migrateVolumes) {
                    Text("Transfer volumes")
                    Text("Coolify can copy persistent volumes when it manages both servers.")
                }
            } footer: {
                Text("Coolify stops \(resourceName) either way, and it has to be deployed again.")
            }
        }
        .confirmationDialog("Migrate \(resourceName)?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Migrate") { Task { await migrate() } }
        } message: {
            Text(confirmation)
        }
        .task {
            catalog.prepare(client)
            await catalog.load()
        }
    }

    private var confirmation: String {
        if migrateVolumes {
            return "Coolify stops \(resourceName). It can copy persistent volumes when it manages both servers. "
                + "\(resourceName) has to be deployed again afterward."
        }
        return "Coolify stops \(resourceName) and does not copy its persistent volumes. "
            + "\(resourceName) has to be deployed again afterward."
    }

    private func migrate() async {
        guard !isSaving, let client, let destinationUUID else {
            failure = client == nil ? "Hotify is not connected to this instance." : failure
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await client.migrateResource(
                PlacementOwner(route),
                MigrateResourceRequest(destinationUUID: destinationUUID, migrateVolumes: migrateVolumes))
            dismiss()
        } catch {
            failure = placementFailure(error)
        }
    }
}

#Preview {
    @Previewable @State var catalog = DestinationCatalog(
        servers: [
            Server(uuid: "s1", name: "localhost", isReachable: true),
            Server(uuid: "s2", name: "edge-01", isReachable: false),
        ],
        destinations: [
            Destination(uuid: "d1", name: "coolify", network: "coolify", serverUUID: "s1")
        ],
        serverUUID: "s1",
        destinationUUID: "d1"
    )
    MigrateSheet(resourceName: "postgres", route: .database("db"), client: nil, catalog: catalog)
}

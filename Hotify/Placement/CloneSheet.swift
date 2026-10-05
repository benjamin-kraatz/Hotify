import CoolifyAPI
import SwiftUI

/// Clones a resource onto a server destination. Volume data is copied only when asked, and that asks first.
struct CloneSheet: View {
    var resourceName: String
    var route: ResourceRoute
    var client: CoolifyClient?

    @Bindable var catalog: DestinationCatalog
    @State private var name = ""
    @State private var cloneVolumes = false
    @State private var confirmVolumes = false
    @State private var isSaving = false
    @State private var failure: String?
    @SwiftUI.Environment(\.dismiss) private var dismiss

    private var destinationUUID: String? {
        let uuid = catalog.destinationUUID ?? ""
        return uuid.isEmpty ? nil : uuid
    }

    private var canClone: Bool { destinationUUID != nil && !isSaving && !catalog.isLoadingDestinations }

    var body: some View {
        PlacementChrome(
            title: "Clone", actionTitle: "Clone", canAct: canClone, isBusy: isSaving, failure: failure,
            onAct: {
                if cloneVolumes {
                    confirmVolumes = true
                } else {
                    Task { await clone() }
                }
            }
        ) {
            Section {
                TextField("Name", text: $name, prompt: Text("Keep \(resourceName)"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            } header: {
                Text("Name")
            } footer: {
                Text("Leave this blank to keep the current name.")
            }

            DestinationChoice(catalog: catalog)

            Section {
                Toggle(isOn: $cloneVolumes) {
                    Text("Clone volumes")
                    Text("Copies the volume data into the clone. Off leaves the clone with empty volumes.")
                }
            }
        }
        .confirmationDialog(
            "Clone \(resourceName) with its volumes?", isPresented: $confirmVolumes, titleVisibility: .visible
        ) {
            Button("Clone Volumes") { Task { await clone() } }
        } message: {
            Text("Coolify copies \(resourceName)'s volume data into the clone.")
        }
        .task {
            catalog.prepare(client)
            await catalog.load()
        }
    }

    private func clone() async {
        guard !isSaving, let client, let destinationUUID else {
            failure = client == nil ? "Hotify is not connected to this instance." : failure
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await client.cloneResource(
                PlacementOwner(route),
                CloneResourceRequest(
                    destinationUUID: destinationUUID,
                    name: name,
                    cloneVolumes: cloneVolumes
                ))
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
            Destination(uuid: "d1", name: "coolify", network: "coolify", serverUUID: "s1"),
            Destination(uuid: "d2", name: "apps", network: "apps", serverUUID: "s1"),
        ],
        serverUUID: "s1",
        destinationUUID: "d1"
    )
    CloneSheet(resourceName: "marketing-site", route: .application("app"), client: nil, catalog: catalog)
}

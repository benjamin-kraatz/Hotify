import CoolifyAPI
import SwiftUI

/// Picks a server and, when it has more than one, the network a clone or migration uses.
struct DestinationChoice: View {
    @Bindable var catalog: DestinationCatalog

    var body: some View {
        Section {
            if !catalog.hasLoaded, catalog.problem == nil || catalog.isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading servers…")
                        .foregroundStyle(.secondary)
                }
            } else if let problem = catalog.problem, catalog.servers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.glow)
                    Button("Try Again", systemImage: "arrow.clockwise") {
                        Task { await catalog.load() }
                    }
                }
            } else if catalog.hostServers.isEmpty {
                Text("This team has no server that can run a resource.")
                    .foregroundStyle(.secondary)
            } else {
                serverPicker
                destinations
            }
        } header: {
            Text("Destination")
        }
    }

    private var serverPicker: some View {
        Picker(
            selection: Binding(
                get: { catalog.serverUUID ?? "" },
                set: { catalog.selectServer($0) })
        ) {
            ForEach(catalog.hostServers, id: \.uuid) { server in
                Text(catalog.isReachable(server) ? server.name : "\(server.name) (unreachable)")
                    .tag(server.uuid)
            }
        } label: {
            Label("Server", systemImage: "server.rack")
        }
    }

    @ViewBuilder
    private var destinations: some View {
        if catalog.isLoadingDestinations {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading networks…")
                    .foregroundStyle(.secondary)
            }
        } else if let problem = catalog.problem {
            VStack(alignment: .leading, spacing: 8) {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.glow)
                Button("Try Again", systemImage: "arrow.clockwise") {
                    Task { await catalog.loadDestinations() }
                }
            }
        } else if catalog.destinations.isEmpty {
            Text("This server has no network to place a resource on.")
                .foregroundStyle(.secondary)
        } else {
            Picker(
                selection: Binding(
                    get: { catalog.destinationUUID ?? "" },
                    set: { catalog.destinationUUID = $0 })
            ) {
                ForEach(catalog.destinations) { destination in
                    Text(destination.network.map { "\(destination.name) (\($0))" } ?? destination.name)
                        .tag(destination.uuid)
                }
            } label: {
                Label("Network", systemImage: "network")
            }
        }
    }
}

extension DestinationCatalog {
    /// The sheet's head once a server is picked: the server, and the network when there is a choice of one.
    func destinationJourney(
        resourceName: String, heat: Heat, origin: String?, arrowImage: String = "arrow.right"
    ) -> PlacementJourney? {
        guard let server else { return nil }
        let network = destinations.count > 1 ? destination?.name : nil
        return PlacementJourney(
            resourceName: resourceName,
            heat: heat,
            origin: origin,
            destination: network.map { "\(server.name) · \($0)" } ?? server.name,
            destinationKind: isReachable(server) ? "Server" : "Server, unreachable",
            destinationImage: "server.rack",
            arrowImage: arrowImage
        )
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
    Form {
        DestinationChoice(catalog: catalog)
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 240)
}

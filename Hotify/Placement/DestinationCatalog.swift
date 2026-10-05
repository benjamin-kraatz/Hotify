import CoolifyAPI
import Foundation

/// The servers and networks a clone or a migration can land on.
@Observable
final class DestinationCatalog {
    var servers: [Server]
    var destinations: [Destination]
    var serverUUID: String?
    var destinationUUID: String?
    var isLoading = false
    var isLoadingDestinations = false
    var hasLoaded: Bool
    var problem: String?

    private var client: CoolifyClient?

    init(
        servers: [Server] = [],
        destinations: [Destination] = [],
        serverUUID: String? = nil,
        destinationUUID: String? = nil
    ) {
        let hosts = servers.filter { $0.settings?.isBuildServer != true }
        self.servers = hosts
        self.destinations = destinations
        self.serverUUID = serverUUID ?? hosts.first?.uuid
        if let destinationUUID {
            self.destinationUUID = destinationUUID
        } else if destinations.count == 1 {
            self.destinationUUID = destinations[0].uuid
        } else {
            self.destinationUUID = nil
        }
        hasLoaded = !servers.isEmpty
    }

    /// Servers a resource can run on. A build server only builds images, and Coolify refuses to place one there.
    var hostServers: [Server] { servers.filter { $0.settings?.isBuildServer != true } }

    var server: Server? { hostServers.first { $0.uuid == serverUUID } }
    var destination: Destination? { destinations.first { $0.uuid == destinationUUID } }

    func isReachable(_ server: Server) -> Bool {
        (server.isReachable ?? server.settings?.isReachable) != false
            && (server.isUsable ?? server.settings?.isUsable) != false
    }

    func prepare(_ client: CoolifyClient?) {
        self.client = client
    }

    func load() async {
        guard let client, !hasLoaded, !isLoading else { return }
        isLoading = true
        problem = nil
        defer { isLoading = false }
        do {
            let loaded = try await client.servers()
            servers = loaded.filter { $0.settings?.isBuildServer != true }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if serverUUID == nil || hostServers.contains(where: { $0.uuid == serverUUID }) == false {
                serverUUID = hostServers.first(where: isReachable)?.uuid ?? hostServers.first?.uuid
            }
            hasLoaded = true
            if serverUUID != nil { isLoadingDestinations = true }
            isLoading = false
            await loadDestinations()
        } catch is CancellationError {
            return
        } catch {
            problem = placementFailure(error)
        }
    }

    func selectServer(_ uuid: String) {
        guard serverUUID != uuid else { return }
        serverUUID = uuid
        destinationUUID = nil
        destinations = []
        problem = nil
        isLoadingDestinations = true
        Task { await loadDestinations() }
    }

    func loadDestinations() async {
        guard let client, let serverUUID else {
            isLoadingDestinations = false
            return
        }
        let requested = serverUUID
        isLoadingDestinations = true
        defer {
            if self.serverUUID == requested { isLoadingDestinations = false }
        }
        do {
            let loaded = try await client.destinations(onServer: requested)
            guard self.serverUUID == requested else { return }
            destinations = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if destinations.count == 1 {
                destinationUUID = destinations[0].uuid
            } else if destinations.contains(where: { $0.uuid == destinationUUID }) == false {
                destinationUUID = nil
            }
        } catch is CancellationError {
            return
        } catch {
            guard self.serverUUID == requested else { return }
            destinations = []
            destinationUUID = nil
            problem = placementFailure(error)
        }
    }
}

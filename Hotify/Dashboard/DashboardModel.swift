import CoolifyAPI
import Foundation

/// Polls one Coolify instance and runs start, stop, and restart on its services.
@Observable
final class DashboardModel {
    var version = ""
    var teamName = ""
    var projects: [Project] = []
    var servers: [Server] = []
    var services: [Service] = []
    var loadError: String?
    var actionError: String?
    var isLoading = false
    var busyServiceIDs: Set<String> = []
    var lastUpdated: Date?

    private var client: CoolifyClient?
    private var pollTask: Task<Void, Never>?

    func bind(_ client: CoolifyClient?) {
        pollTask?.cancel()
        self.client = client
        version = ""
        teamName = ""
        projects = []
        servers = []
        services = []
        loadError = nil
        actionError = nil
        lastUpdated = nil
        guard client != nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                if Task.isCancelled { return }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        guard let client else { return }
        if services.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            async let version = client.version()
            async let team = client.currentTeam()
            async let projects = client.projects()
            async let servers = client.servers()
            async let services = client.services()
            self.version = try await version
            teamName = try await team.name
            self.projects = try await projects
            self.servers = try await servers
            self.services = try await services
            loadError = nil
            lastUpdated = .now
        } catch is CancellationError {
            // A new poll replaced this one. Leave the screen as the next refresh finds it.
            return
        } catch {
            loadError = (error as? CoolifyError)?.message ?? error.localizedDescription
        }
    }

    func perform(_ action: ServiceAction, on service: Service) async {
        guard let client else { return }
        busyServiceIDs.insert(service.id)
        defer { busyServiceIDs.remove(service.id) }
        do {
            switch action {
            case .start:
                _ = try await client.startService(service.id)
            case .stop:
                // The list control stops the service and leaves volumes in place.
                _ = try await client.stopService(service.id, dockerCleanup: false)
            case .restart:
                _ = try await client.restartService(service.id)
            }
            actionError = nil
            await refresh()
        } catch is CancellationError {
            return
        } catch {
            actionError = (error as? CoolifyError)?.message ?? error.localizedDescription
        }
    }
}

enum ServiceAction: String, Identifiable {
    case start
    case stop
    case restart

    var id: String { rawValue }

    var title: String {
        switch self {
        case .start: "Start"
        case .stop: "Stop"
        case .restart: "Restart"
        }
    }
}

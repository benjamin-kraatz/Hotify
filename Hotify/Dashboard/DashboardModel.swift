import CoolifyAPI
import Foundation

/// Polls one Coolify instance and runs start, stop, and restart on its applications, databases, and services.
@Observable
final class DashboardModel {
    var version = ""
    var teamName = ""
    var projects: [Project] = []
    var servers: [Server] = []
    var applications: [Application] = []
    var databases: [Database] = []
    var services: [Service] = []
    var loadError: String?
    var actionError: String?
    var isLoading = false
    var pending: [BusyTarget: ResourceAction] = [:]
    var lastUpdated: Date?

    private var client: CoolifyClient?
    private var pollTask: Task<Void, Never>?
    private var generation = 0

    func bind(_ client: CoolifyClient?) {
        generation += 1
        pollTask?.cancel()
        self.client = client
        loadError = nil
        actionError = nil
        pending = [:]
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
        generation += 1
        pollTask?.cancel()
        pollTask = nil
        pending = [:]
    }

    func refresh() async {
        guard let client else { return }
        if lastUpdated == nil {
            isLoading = true
        }
        defer { isLoading = false }
        do {
            async let version = client.version()
            async let team = client.currentTeam()
            async let projects = client.projects()
            async let servers = client.servers()
            async let applications = client.applications()
            async let databases = client.databases()
            async let services = client.services()
            self.version = try await version
            teamName = try await team.name
            self.projects = try await projects
            self.servers = try await servers
            self.applications = try await applications
            self.databases = try await databases
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

    var snapshot: DashboardSnapshot {
        DashboardSnapshot(
            teamName: teamName,
            version: version,
            servers: servers.map { server in
                ServerLine(
                    id: server.uuid.isEmpty ? server.name : server.uuid,
                    name: server.name,
                    isReachable: server.isReachable ?? server.settings?.isReachable
                )
            },
            resources: applications.map { ResourceSummary(application: $0) }
                + databases.map { ResourceSummary(database: $0) }
                + services.map { ResourceSummary(service: $0) },
            pending: pending,
            loadError: loadError,
            actionError: actionError,
            isLoading: isLoading,
            hasLoaded: lastUpdated != nil
        )
    }

    /// Runs an action on whichever resource the route points at, if it is still listed.
    func perform(_ action: ResourceAction, route: ResourceRoute) async {
        switch route {
        case .application(let uuid):
            guard let application = applications.first(where: { $0.uuid == uuid }) else { return }
            await perform(action, on: application)
        case .database(let uuid):
            guard let database = databases.first(where: { $0.uuid == uuid }) else { return }
            await perform(action, on: database)
        case .service(let uuid):
            guard let service = services.first(where: { $0.uuid == uuid }) else { return }
            await perform(action, on: service)
        }
    }

    func perform(_ action: ResourceAction, on application: Application) async {
        await run(action, target: .application(application.uuid)) { client in
            switch action {
            case .start:
                _ = try await client.startApplication(application.uuid)
            case .stop:
                // The list control stops the resource and leaves volumes in place.
                _ = try await client.stopApplication(application.uuid, dockerCleanup: false)
            case .restart:
                _ = try await client.restartApplication(application.uuid)
            }
        }
    }

    func perform(_ action: ResourceAction, on database: Database) async {
        await run(action, target: .database(database.uuid)) { client in
            switch action {
            case .start:
                _ = try await client.startDatabase(database.uuid)
            case .stop:
                // The list control stops the resource and leaves volumes in place.
                _ = try await client.stopDatabase(database.uuid, dockerCleanup: false)
            case .restart:
                _ = try await client.restartDatabase(database.uuid)
            }
        }
    }

    func perform(_ action: ResourceAction, on service: Service) async {
        await run(action, target: .service(service.id)) { client in
            switch action {
            case .start:
                _ = try await client.startService(service.id)
            case .stop:
                // The list control stops the resource and leaves volumes in place.
                _ = try await client.stopService(service.id, dockerCleanup: false)
            case .restart:
                _ = try await client.restartService(service.id)
            }
        }
    }

    private func run(
        _ action: ResourceAction,
        target: BusyTarget,
        operation: (CoolifyClient) async throws -> Void
    ) async {
        guard let client else { return }
        let generation = self.generation
        pending[target] = action
        defer {
            if generation == self.generation {
                pending[target] = nil
            }
        }
        do {
            try await operation(client)
            guard generation == self.generation else { return }
            actionError = nil
            await refresh()
        } catch is CancellationError {
            return
        } catch {
            guard generation == self.generation else { return }
            actionError = (error as? CoolifyError)?.message ?? error.localizedDescription
        }
    }
}

enum BusyTarget: Hashable {
    case application(String)
    case database(String)
    case service(String)
}

enum ResourceAction: String, Identifiable, CaseIterable {
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

    var systemImage: String {
        switch self {
        case .start: "play.fill"
        case .stop: "stop.fill"
        case .restart: "arrow.clockwise"
        }
    }
}

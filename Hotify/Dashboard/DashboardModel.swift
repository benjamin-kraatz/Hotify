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
    var busyTargets: Set<BusyTarget> = []
    var lastUpdated: Date?

    private var client: CoolifyClient?
    private var pollTask: Task<Void, Never>?
    private var generation = 0

    func bind(_ client: CoolifyClient?) {
        generation += 1
        pollTask?.cancel()
        self.client = client
        version = ""
        teamName = ""
        projects = []
        servers = []
        applications = []
        databases = []
        services = []
        loadError = nil
        actionError = nil
        busyTargets = []
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
        generation += 1
        pollTask?.cancel()
        pollTask = nil
        busyTargets = []
    }

    func refresh() async {
        guard let client else { return }
        if applications.isEmpty, databases.isEmpty, services.isEmpty {
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

    func perform(_ action: ResourceAction, on application: Application) async {
        await run(target: .application(application.uuid)) { client in
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
        await run(target: .database(database.uuid)) { client in
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
        await run(target: .service(service.id)) { client in
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
        target: BusyTarget,
        operation: (CoolifyClient) async throws -> Void
    ) async {
        guard let client else { return }
        let generation = self.generation
        busyTargets.insert(target)
        defer {
            if generation == self.generation {
                busyTargets.remove(target)
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

enum ResourceAction: String, Identifiable {
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

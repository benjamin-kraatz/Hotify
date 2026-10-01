import CoolifyAPI
import Foundation

/// Polls one Coolify instance and runs actions on its applications, databases, and services.
@Observable
final class DashboardModel {
    var version = ""
    var teamName = ""
    var projects: [Project] = []
    var servers: [Server] = []
    var applications: [Application] = []
    var databases: [Database] = []
    var services: [Service] = []
    /// Production deployments that are queued or building, across every application.
    var activeDeployments: [Deployment] = []
    /// Preview deployments that are queued or building. Kept apart so a preview never marks production busy.
    var activePreviewDeployments: [Deployment] = []
    var places: [Int: ResourcePlace] = [:]
    var loadError: String?
    var actionError: String?
    var isLoading = false
    var transitions: [BusyTarget: ResourceTransition] = [:]
    var lastUpdated: Date?

    private var client: CoolifyClient?
    private var pollTask: Task<Void, Never>?
    private var generation = 0
    private var placesLoadedAt: Date?
    private var placedProjectIDs: Set<String> = []

    /// Project names change rarely, and each project is its own request.
    private static let placesMaxAge: TimeInterval = 300

    func bind(_ client: CoolifyClient?) {
        generation += 1
        pollTask?.cancel()
        self.client = client
        loadError = nil
        actionError = nil
        // Keep what was in flight when the user switched away, so a start does not flash back to "Exited" on return.
        // A request cut off by the switch may have landed, so let the next poll decide.
        for target in transitions.keys {
            transitions[target]?.isSending = false
        }
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
    }

    func refresh() async {
        guard let client else { return }
        let generation = self.generation
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
            // The queue only adds a "Deploying" state. A failure here should not blank the whole dashboard.
            async let deployments = try? client.runningDeployments()
            let loadedProjects = try await projects
            let loadedApplications = try await applications
            let loadedDatabases = try await databases
            let loadedServices = try await services
            let loadedVersion = try await version
            let loadedTeam = try await team.name
            let loadedServers = try await servers
            let loadedDeployments = await deployments
            guard generation == self.generation else { return }
            self.version = loadedVersion
            teamName = loadedTeam
            self.projects = loadedProjects
            self.servers = loadedServers
            self.applications = loadedApplications
            self.databases = loadedDatabases
            self.services = loadedServices
            if let loadedDeployments {
                activeDeployments = loadedDeployments.filter { !$0.isPreview }
                activePreviewDeployments = loadedDeployments.filter(\.isPreview)
            }
            loadError = nil
            lastUpdated = .now
            await loadPlacesIfNeeded(client, generation: generation)
            settleTransitions()
        } catch is CancellationError {
            // A new poll replaced this one. Leave the screen as the next refresh finds it.
            return
        } catch {
            guard generation == self.generation else { return }
            loadError = (error as? CoolifyError)?.message ?? error.localizedDescription
        }
    }

    /// Fetches each project for its environments when a project or environment appears, or the names are stale.
    private func loadPlacesIfNeeded(_ client: CoolifyClient, generation: Int) async {
        let projectIDs = Set(projects.map(\.uuid))
        let environmentIDs = Set(
            applications.compactMap(\.environmentID) + databases.compactMap(\.environmentID)
                + services.compactMap(\.environmentID)
        )
        let age = placesLoadedAt.map { Date.now.timeIntervalSince($0) } ?? .infinity
        let hasUnplaced = !environmentIDs.subtracting(places.keys).isEmpty
        // An unplaced resource retries once a minute, not every poll, in case its project stays out of reach.
        guard projectIDs != placedProjectIDs || age > Self.placesMaxAge || (hasUnplaced && age > 60) else { return }

        let detailed = await withTaskGroup(of: Project?.self) { group in
            for project in projects {
                group.addTask { try? await client.project(project.uuid) }
            }
            var loaded: [Project] = []
            for await project in group {
                if let project {
                    loaded.append(project)
                }
            }
            return loaded
        }
        guard generation == self.generation, !detailed.isEmpty || projects.isEmpty else { return }
        places = ResourcePlace.index(detailed)
        placedProjectIDs = projectIDs
        placesLoadedAt = .now
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
            resources: applications.map { application in
                ResourceSummary(
                    application: application,
                    place: application.environmentID.flatMap { places[$0] },
                    activeDeployment: activeDeployment(for: application),
                    activePreviews: deployments(for: application, in: activePreviewDeployments)
                )
            }
                + databases.map { ResourceSummary(database: $0, place: $0.environmentID.flatMap { places[$0] }) }
                + services.map { ResourceSummary(service: $0, place: $0.environmentID.flatMap { places[$0] }) },
            pending: transitions.mapValues(\.action),
            loadError: loadError,
            actionError: actionError,
            isLoading: isLoading,
            hasLoaded: lastUpdated != nil
        )
    }

    private func activeDeployment(for application: Application) -> Deployment? {
        deployments(for: application, in: activeDeployments).first
    }

    private func deployments(for application: Application, in list: [Deployment]) -> [Deployment] {
        guard let id = application.id else {
            return list.filter { $0.applicationName == application.name }
        }
        return list.filter { $0.applicationID == id }
    }

    /// Runs an action on whichever resource the route points at, if it is still listed.
    func perform(_ action: ResourceAction, route: ResourceRoute) async {
        guard let client, state(of: route.busyTarget) != nil else { return }
        let generation = self.generation
        let target = route.busyTarget
        transitions[target] = ResourceTransition(action: action)
        do {
            try await send(action, route: route, client: client)
            guard generation == self.generation else { return }
            actionError = nil
            transitions[target]?.isSending = false
            await refresh()
        } catch is CancellationError {
            return
        } catch {
            guard generation == self.generation else { return }
            transitions[target] = nil
            actionError = (error as? CoolifyError)?.message ?? error.localizedDescription
        }
    }

    private func send(_ action: ResourceAction, route: ResourceRoute, client: CoolifyClient) async throws {
        switch (route, action) {
        case (.application(let uuid), .start):
            _ = try await client.startApplication(uuid)
        case (.application(let uuid), .deploy):
            _ = try await client.deploy(uuid: uuid)
        case (.application(let uuid), .restart):
            _ = try await client.restartApplication(uuid)
        case (.application(let uuid), .stop):
            // The list control stops the resource and leaves volumes in place.
            _ = try await client.stopApplication(uuid, dockerCleanup: false)
        case (.application(let uuid), .cancelDeployment):
            guard
                let application = applications.first(where: { $0.uuid == uuid }),
                let deployment = activeDeployment(for: application)
            else { return }
            _ = try await client.cancelDeployment(deployment.deploymentUUID)
        case (.database(let uuid), .start):
            _ = try await client.startDatabase(uuid)
        case (.database(let uuid), .restart):
            _ = try await client.restartDatabase(uuid)
        case (.database(let uuid), .stop):
            _ = try await client.stopDatabase(uuid, dockerCleanup: false)
        case (.service(let uuid), .start):
            _ = try await client.startService(uuid)
        case (.service(let uuid), .restart):
            _ = try await client.restartService(uuid)
        case (.service(let uuid), .stop):
            _ = try await client.stopService(uuid, dockerCleanup: false)
        case (.database, .deploy), (.database, .cancelDeployment), (.service, .deploy), (.service, .cancelDeployment):
            // Only applications deploy. The action lists never offer these.
            return
        }
    }

    /// Ends every transition whose resource reached its new state, and says so when one never did.
    private func settleTransitions() {
        for (target, var transition) in transitions {
            guard let current = state(of: target) else {
                transitions[target] = nil
                continue
            }
            let outcome = transition.observe(status: current.status, isDeploying: current.isDeploying)
            switch outcome {
            case nil:
                transitions[target] = transition
            case .done:
                transitions[target] = nil
            case .gaveUp:
                transitions[target] = nil
                actionError = Self.failureMessage(
                    transition.action, name: current.name, deployed: transition.sawDeployment)
            }
        }
    }

    private static func failureMessage(_ action: ResourceAction, name: String, deployed: Bool) -> String {
        if action == .stop {
            return "\(name) is still running. Coolify may not have been able to stop it."
        }
        if deployed {
            return "The deployment of \(name) ended, but it isn't running. Open Deployments to see what went wrong."
        }
        return "\(name) hasn't come up yet. Check its logs, or look at it in Coolify."
    }

    /// What a poll says about the resource an action targets.
    private struct TargetState {
        var name: String
        var status: String?
        var isDeploying = false
    }

    private func state(of target: BusyTarget) -> TargetState? {
        switch target {
        case .application(let uuid):
            guard let application = applications.first(where: { $0.uuid == uuid }) else { return nil }
            return TargetState(
                name: application.name,
                status: application.status,
                isDeploying: activeDeployment(for: application) != nil
            )
        case .database(let uuid):
            guard let database = databases.first(where: { $0.uuid == uuid }) else { return nil }
            return TargetState(name: database.name ?? uuid, status: database.status)
        case .service(let uuid):
            guard let service = services.first(where: { $0.uuid == uuid }) else { return nil }
            return TargetState(name: service.displayName, status: service.status)
        }
    }
}

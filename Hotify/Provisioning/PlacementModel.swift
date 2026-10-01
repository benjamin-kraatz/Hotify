import CoolifyAPI
import Foundation

/// Loads the servers, projects, and networks a new service can go to, and holds the one picked.
@Observable
final class PlacementModel {
    var servers: [Server] = []
    /// Fetched one by one, since only the detail carries environments.
    var projects: [Project] = []
    /// The networks on the picked server. Empty when the server has one, or the list could not load.
    var destinations: [Destination] = []
    var placement = Placement()
    var isLoading = false
    var hasLoaded = false
    var problem: ProvisioningProblem?
    /// A project or environment being created from the picker.
    var isCreatingPlace = false
    /// The picked server's networks are loading. Creating waits, since a server with several needs one named.
    var isLoadingDestinations = false

    private var client: CoolifyClient?
    private var instanceID: UUID?

    init(servers: [Server] = [], projects: [Project] = [], placement: Placement = Placement()) {
        self.servers = servers
        self.projects = projects
        self.placement = placement
        hasLoaded = !servers.isEmpty
    }

    func prepare(_ client: CoolifyClient?, instanceID: UUID?) {
        self.client = client
        self.instanceID = instanceID
    }

    /// Servers a service can go to. Build servers only build images, and Coolify refuses to place resources there.
    var hostServers: [Server] {
        servers.filter { $0.settings?.isBuildServer != true }
    }

    var server: Server? { servers.first { $0.uuid == placement.serverUUID } }
    var project: Project? { projects.first { $0.uuid == placement.projectUUID } }
    var environments: [Environment] { (project?.environments ?? []).filter { $0.uuid != nil } }
    var environment: Environment? { environments.first { $0.uuid == placement.environmentUUID } }

    /// The server's network. Hotify sends one only when the server offers a choice.
    var destination: Destination? { destinations.first { $0.uuid == placement.destinationUUID } }

    func isReachable(_ server: Server) -> Bool {
        (server.isReachable ?? server.settings?.isReachable) != false
            && (server.isUsable ?? server.settings?.isUsable) != false
    }

    func load() async {
        guard let client, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let servers = client.servers()
            async let projects = client.projects()
            let loadedServers = try await servers
            let summaries = try await projects
            let detailed = await withTaskGroup(of: Project?.self) { group in
                for project in summaries {
                    group.addTask { try? await client.project(project.uuid) }
                }
                var loaded: [Project] = []
                for await project in group {
                    if let project { loaded.append(project) }
                }
                return loaded
            }
            self.servers = loadedServers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            self.projects = detailed.sorted(by: Self.byName)
            problem = nil
            hasLoaded = true
            restore()
            await loadDestinations()
        } catch is CancellationError {
            return
        } catch {
            problem = ProvisioningProblem(error)
        }
    }

    /// Picks the server at once, so the picker shows it, and loads its networks behind it.
    func selectServer(_ uuid: String) {
        guard placement.serverUUID != uuid else { return }
        placement.serverUUID = uuid
        placement.destinationUUID = nil
        destinations = []
        Task { await loadDestinations() }
    }

    func selectProject(_ uuid: String) {
        placement.projectUUID = uuid
        placement.environmentUUID = Self.preferredEnvironment(in: project)?.uuid
    }

    func selectEnvironment(_ uuid: String) {
        placement.environmentUUID = uuid
    }

    /// Creates a project and puts the service in it. Coolify gives every new project a `production` environment.
    /// Returns the project's uuid. Throws a message for the form that named it.
    func createProject(named name: String) async throws -> String {
        guard let client else { throw PlaceWriteError(message: "Hotify is not connected to this instance.") }
        isCreatingPlace = true
        defer { isCreatingPlace = false }
        do {
            let created = try await client.createProject(name: name)
            let project = try await client.project(created.uuid)
            projects.append(project)
            projects.sort(by: Self.byName)
            selectProject(project.uuid)
            return created.uuid
        } catch {
            throw PlaceWriteError(error)
        }
    }

    /// Creates an environment in the picked project and puts the service in it. Returns the environment's uuid.
    /// Throws a message for the form that named it.
    func createEnvironment(named name: String) async throws -> String {
        guard let client, let projectUUID = placement.projectUUID else {
            throw PlaceWriteError(message: "Pick a project for the environment first.")
        }
        isCreatingPlace = true
        defer { isCreatingPlace = false }
        do {
            let created = try await client.createEnvironment(name: name, inProject: projectUUID)
            let project = try await client.project(projectUUID)
            if let index = projects.firstIndex(where: { $0.uuid == projectUUID }) {
                projects[index] = project
            }
            placement.environmentUUID = created.uuid
            return created.uuid
        } catch {
            throw PlaceWriteError(error)
        }
    }

    func remember() {
        guard let instanceID else { return }
        placement.remember(for: instanceID)
    }

    /// The last placement on this instance where it still exists, else the first reachable server, the first project,
    /// and its production environment.
    private func restore() {
        let remembered = instanceID.flatMap(Placement.remembered(for:))
        let hosts = hostServers
        placement.serverUUID =
            hosts.first { $0.uuid == remembered?.serverUUID }?.uuid
            ?? hosts.first(where: isReachable)?.uuid ?? hosts.first?.uuid
        if let remembered, let project = projects.first(where: { $0.uuid == remembered.projectUUID }) {
            placement.projectUUID = project.uuid
            let environments = project.environments ?? []
            placement.environmentUUID =
                environments.first { $0.uuid == remembered.environmentUUID }?.uuid
                ?? Self.preferredEnvironment(in: project)?.uuid
        } else if let first = projects.first {
            selectProject(first.uuid)
        }
        placement.destinationUUID = remembered?.serverUUID == placement.serverUUID ? remembered?.destinationUUID : nil
    }

    /// Lists the server's networks. A failure is not fatal: with one network Coolify picks it on its own.
    private func loadDestinations() async {
        guard let client, let serverUUID = placement.serverUUID else { return }
        isLoadingDestinations = true
        let loaded = (try? await client.destinations(onServer: serverUUID)) ?? []
        guard placement.serverUUID == serverUUID else { return }
        isLoadingDestinations = false
        destinations = loaded.count > 1 ? loaded : []
        if destinations.isEmpty {
            placement.destinationUUID = nil
        } else if destination == nil {
            placement.destinationUUID = destinations.first?.uuid
        }
    }

    private static func preferredEnvironment(in project: Project?) -> Environment? {
        let environments = (project?.environments ?? []).filter { $0.uuid != nil }
        return environments.first { $0.name == "production" } ?? environments.first
    }

    private static func byName(_ lhs: Project, _ rhs: Project) -> Bool {
        (lhs.name ?? lhs.uuid).localizedStandardCompare(rhs.name ?? rhs.uuid) == .orderedAscending
    }
}

import CoolifyAPI
import Foundation

/// Refreshes selected resources while the opt-in menu bar companion is enabled.
@Observable
final class MenuBarModel {
    static let enabledKey = "hotify.menuBar.enabled"
    var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: Self.enabledKey)
            restartPolling()
        }
    }
    private(set) var watched: [WatchedResource]
    var snapshots: [String: MenuBarResourceState] = [:]
    var navigation: MenuBarNavigation?
    var refreshing = false
    /// Why the last action from the menu bar failed or never finished.
    var actionError: String?
    /// Actions Coolify accepted, by watched resource, until a check shows their result.
    private var transitions: [String: ResourceTransition] = [:]
    private let defaults: UserDefaults
    private var store: InstanceStore?
    private var pollTask: Task<Void, Never>?
    private var generation = 0

    init(defaults: UserDefaults = .standard, preview: Bool = false) {
        self.defaults = defaults
        enabled = !preview && defaults.bool(forKey: Self.enabledKey)
        watched =
            preview
            ? []
            : (defaults.data(forKey: "hotify.menuBar.resources").flatMap {
                try? JSONDecoder().decode([WatchedResource].self, from: $0)
            } ?? [])
    }

    func connect(_ store: InstanceStore) {
        self.store = store
        restartPolling()
    }

    func state(for resource: WatchedResource) -> MenuBarResourceState {
        var state = snapshots[resource.id] ?? MenuBarResourceState()
        state.pendingAction = transitions[resource.id]?.action
        return state
    }

    /// One heat per watched resource, for the strip and the menu bar icon.
    var heats: [Heat] {
        watched.map { state(for: $0).heat }
    }

    /// The newest successful check across every watched resource.
    var lastChecked: Date? {
        watched.compactMap { state(for: $0).updatedAt }.max()
    }

    func isWatching(_ resource: WatchedResource) -> Bool {
        watched.contains { $0.id == resource.id }
    }

    func add(_ resource: WatchedResource) {
        guard !watched.contains(where: { $0.id == resource.id }) else { return }
        watched.append(resource)
        persist()
        restartPolling()
    }

    func remove(_ resource: WatchedResource) {
        watched.removeAll { $0.id == resource.id }
        snapshots.removeValue(forKey: resource.id)
        transitions.removeValue(forKey: resource.id)
        persist()
        restartPolling()
    }

    func open(_ resource: WatchedResource) {
        guard let route = resource.route else { return }
        navigation = MenuBarNavigation(instanceID: resource.instanceID, route: route)
    }

    /// Runs an action on a watched resource, then keeps it in its in-between state until a check shows the result.
    func perform(_ action: ResourceAction, on entry: WatchedResource) async {
        guard let store, let route = entry.route,
            let instance = store.instances.first(where: { $0.id == entry.instanceID }),
            let client = store.client(for: instance)
        else { return }
        let deploymentID = state(for: entry).resource?.activeDeploymentID
        transitions[entry.id] = ResourceTransition(action: action)
        LocalActions.note(action, route)
        do {
            try await client.run(action, on: route, deploymentID: deploymentID)
            transitions[entry.id]?.isSending = false
            actionError = nil
            WidgetRefresh.all()
            await refresh()
        } catch is CancellationError {
            transitions[entry.id] = nil
        } catch {
            transitions[entry.id] = nil
            actionError = (error as? CoolifyError)?.message ?? error.localizedDescription
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(watched) { defaults.set(data, forKey: "hotify.menuBar.resources") }
    }

    private func restartPolling() {
        generation += 1
        pollTask?.cancel()
        pollTask = nil
        refreshing = false
        guard enabled, store != nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
    }

    func refresh() async {
        guard enabled, let store, !refreshing else { return }
        let generation = self.generation
        refreshing = true
        defer { if generation == self.generation { refreshing = false } }
        for (id, entries) in Dictionary(grouping: watched, by: \.instanceID) {
            guard generation == self.generation, !Task.isCancelled else { return }
            guard let instance = store.instances.first(where: { $0.id == id }), let client = store.client(for: instance)
            else {
                for entry in entries {
                    snapshots[entry.id] = MenuBarResourceState(message: "Instance or token unavailable")
                }
                continue
            }
            do {
                async let apps = client.applications()
                async let databases = client.databases()
                async let services = client.services()
                async let deployments = client.runningDeployments()
                async let latest = Self.latestDeployments(
                    of: entries.compactMap {
                        if case .application(let uuid) = $0.route { uuid } else { nil }
                    },
                    client: client
                )
                let loaded = try await (apps, databases, services, deployments)
                let latestDeployments = await latest
                guard generation == self.generation, !Task.isCancelled else { return }
                let resources =
                    loaded.0.map { app in
                        // The history also lists a deployment the queue left out, so either one counts.
                        let underway = latestDeployments[app.uuid].flatMap {
                            DeploymentStatus.isUnderway($0.status ?? "") ? $0 : nil
                        }
                        return ResourceSummary(
                            application: app,
                            activeDeployment: loaded.3.first { Self.isProduction($0, of: app) } ?? underway
                        )
                    } + loaded.1.map { ResourceSummary(database: $0) } + loaded.2.map { ResourceSummary(service: $0) }
                for entry in entries {
                    if let resource = resources.first(where: { $0.route == entry.route }) {
                        let deployment = latestDeployments[resource.route.uuid].map {
                            DeploymentLine(deployment: $0, fallbackID: "latest", clientAPIBaseURL: client.apiBaseURL)
                        }
                        snapshots[entry.id] = MenuBarResourceState(
                            resource: resource, latestDeployment: deployment, updatedAt: .now)
                    } else {
                        snapshots[entry.id] = MenuBarResourceState(message: "Resource no longer listed")
                    }
                    settleTransition(of: entry)
                }
            } catch is CancellationError { return } catch {
                guard generation == self.generation else { return }
                for entry in entries {
                    var state = snapshots[entry.id] ?? MenuBarResourceState()
                    state.message = "Unable to refresh"
                    snapshots[entry.id] = state
                }
            }
        }
    }

    /// Ends the entry's transition once its resource reached the new state, and says so when it never did.
    private func settleTransition(of entry: WatchedResource) {
        guard var transition = transitions[entry.id] else { return }
        guard let resource = snapshots[entry.id]?.resource, snapshots[entry.id]?.message == nil else {
            transitions[entry.id] = nil
            return
        }
        switch transition.observe(status: resource.status, isDeploying: resource.isDeploying) {
        case nil:
            transitions[entry.id] = transition
        case .done:
            transitions[entry.id] = nil
        case .gaveUp:
            transitions[entry.id] = nil
            actionError = transition.failureMessage(name: resource.name)
        }
    }

    /// The newest production deployment of each application, by uuid. One that fails to load is left out.
    private static func latestDeployments(of uuids: [String], client: CoolifyClient) async -> [String: Deployment] {
        await withTaskGroup(of: (String, Deployment?).self) { group in
            for uuid in Set(uuids) {
                group.addTask {
                    // The history endpoint cannot filter out previews, so a few rows leave room to skip them.
                    let page = try? await client.applicationDeployments(uuid, take: 5)
                    return (uuid, page?.deployments.first { !$0.isPreview })
                }
            }
            var latest: [String: Deployment] = [:]
            for await (uuid, deployment) in group {
                latest[uuid] = deployment
            }
            return latest
        }
    }

    /// Whether a queued deployment builds this application's production. The list can leave out the numeric id.
    private static func isProduction(_ deployment: Deployment, of application: Application) -> Bool {
        guard !deployment.isPreview else { return false }
        guard let id = application.id else { return deployment.applicationName == application.name }
        return deployment.applicationID == id
    }
}

/// Status always distinguishes cached data from a recent successful refresh.
struct MenuBarResourceState {
    var resource: ResourceSummary?
    /// The newest production deployment of an application, whether it is running, done, or failed.
    var latestDeployment: DeploymentLine?
    var updatedAt: Date?
    var message: String?
    /// An action from the menu bar that has not finished yet.
    var pendingAction: ResourceAction?
    var isStale: Bool { message != nil || updatedAt.map { Date.now.timeIntervalSince($0) > 45 } != false }
    var heat: Heat { isStale ? .unknown : (resource?.heat(pendingAction: pendingAction) ?? .unknown) }

    /// What went wrong, else that the status is old, else the status itself.
    var statusText: String {
        if let message { return message }
        guard let resource, !isStale else { return "Waiting for a fresh status" }
        return StatusLabel.text(for: resource, pendingAction: pendingAction)
    }
}

/// A fresh navigation request, including repeat selections of the same resource.
struct MenuBarNavigation: Equatable {
    var id = UUID()
    var instanceID: UUID
    var route: ResourceRoute
    /// Where in the resource to open, for a widget's link.
    var place: ResourceLink.Place?
}

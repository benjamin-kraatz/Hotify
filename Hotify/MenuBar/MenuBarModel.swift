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
        snapshots[resource.id] ?? MenuBarResourceState()
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
        persist()
        restartPolling()
    }

    func open(_ resource: WatchedResource) {
        guard let route = resource.route else { return }
        navigation = MenuBarNavigation(instanceID: resource.instanceID, route: route)
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
                let loaded = try await (apps, databases, services, deployments)
                guard generation == self.generation, !Task.isCancelled else { return }
                let resources =
                    loaded.0.map { app in
                        ResourceSummary(
                            application: app,
                            activeDeployment: loaded.3.first {
                                !$0.isPreview && $0.applicationID == app.id && app.id != nil
                            })
                    } + loaded.1.map { ResourceSummary(database: $0) } + loaded.2.map { ResourceSummary(service: $0) }
                for entry in entries {
                    if let resource = resources.first(where: { $0.route == entry.route }) {
                        snapshots[entry.id] = MenuBarResourceState(resource: resource, updatedAt: .now)
                    } else {
                        snapshots[entry.id] = MenuBarResourceState(message: "Resource no longer listed")
                    }
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
}

/// Status always distinguishes cached data from a recent successful refresh.
struct MenuBarResourceState {
    var resource: ResourceSummary?
    var updatedAt: Date?
    var message: String?
    var isStale: Bool { message != nil || updatedAt.map { Date.now.timeIntervalSince($0) > 45 } != false }
    var heat: Heat { isStale ? .unknown : (resource?.heat(pendingAction: nil) ?? .unknown) }

    /// What went wrong, else that the status is old, else the status itself.
    var statusText: String {
        if let message { return message }
        guard let resource, !isStale else { return "Waiting for a fresh status" }
        return StatusLabel.text(for: resource, pendingAction: nil)
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

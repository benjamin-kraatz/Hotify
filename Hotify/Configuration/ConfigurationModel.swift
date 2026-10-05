import CoolifyAPI
import Foundation

/// Loads and saves one resource's settings: its name and description, domains, health check, a database's
/// public port, and an application's proxy labels. Edits stay in `draft` until saved, across tab switches, since the
/// detail screen keeps this model.
@Observable
final class ConfigurationModel {
    /// What the user is editing. `nil` until the first load.
    var draft: ResourceConfiguration?
    /// The settings as Coolify last returned them.
    private(set) var saved: ResourceConfiguration?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var loadError: String?
    private(set) var saveError: String?
    /// Domains another resource already answers on, from a save Coolify refused with 409.
    private(set) var conflicts: [DomainConflict] = []
    /// Something Coolify accepted with 200 but did not do.
    private(set) var notice: String?
    /// Set after a change the running resource only picks up with a redeploy or restart.
    var hasUnappliedChanges = false

    private(set) var route: ResourceRoute?
    private var client: CoolifyClient?
    private var generation = 0

    init(saved: ResourceConfiguration? = nil) {
        self.saved = saved
        draft = saved
    }

    var hasChanges: Bool {
        draft != nil && draft != saved
    }

    /// Points the tags editor at the same resource. A nil client leaves preview tags in place.
    func openTags(_ tags: ResourceTagsModel) {
        tags.open(client, route: route)
    }

    /// Clears the previous resource and points later loads and saves at this one.
    func prepare(_ client: CoolifyClient, route: ResourceRoute) {
        generation += 1
        self.client = client
        self.route = route
        draft = nil
        saved = nil
        loadError = nil
        saveError = nil
        conflicts = []
        notice = nil
        hasUnappliedChanges = false
    }

    /// Reads the settings again. Edits in progress are kept unless `replacingEdits` is set.
    func load(replacingEdits: Bool = false) async {
        guard let client, let route else { return }
        let generation = self.generation
        if saved == nil { isLoading = true }
        defer {
            if generation == self.generation { isLoading = false }
        }
        do {
            let loaded = try await Self.read(route, with: client)
            guard generation == self.generation else { return }
            if replacingEdits || !hasChanges {
                draft = loaded
            }
            saved = loaded
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == self.generation else { return }
            loadError = Self.message(for: error)
        }
    }

    func revert() {
        draft = saved
        saveError = nil
        conflicts = []
    }

    /// Sends what changed, then reads the resource back. `force` takes domains another resource already uses.
    func save(force: Bool = false) async {
        guard let client, let route, let draft, let saved, !isSaving else { return }
        let generation = self.generation
        isSaving = true
        defer {
            if generation == self.generation { isSaving = false }
        }
        var sentDomains: [String]?
        var needsApply = false
        do {
            switch route {
            case .application(let uuid):
                let update = draft.applicationUpdate(from: saved, force: force)
                guard !update.isEmpty else { return revert() }
                try await client.updateApplication(uuid, update)
                needsApply = update.needsRedeploy
                sentDomains = update.domains.map(ResourceConfiguration.split)
            case .database(let uuid):
                let update = draft.databaseUpdate(from: saved)
                guard !update.isEmpty else { return revert() }
                try await client.updateDatabase(uuid, update)
                needsApply = update.needsRestart
            case .service(let uuid):
                let update = draft.serviceUpdate(from: saved, force: force)
                guard update != ServiceUpdate() else { return revert() }
                _ = try await client.updateService(uuid, update)
                // Coolify writes a service's domains into its compose labels, which containers read as they start.
                needsApply = update.urls != nil
            }
        } catch let error as CoolifyError where error.statusCode == 409 && !error.conflicts.isEmpty {
            guard generation == self.generation else { return }
            conflicts = error.conflicts
            saveError = nil
            // A service saves its name before it checks domains, so the reload shows what did stick.
            await load()
            return
        } catch is CancellationError {
            return
        } catch {
            guard generation == self.generation else { return }
            saveError = Self.message(for: error)
            return
        }
        guard generation == self.generation else { return }
        conflicts = []
        saveError = nil
        notice = nil
        if needsApply { hasUnappliedChanges = true }
        await load(replacingEdits: true)
        // Coolify answers 200 on a server without a proxy, but keeps the old domains, since nothing would route them.
        if let sentDomains, let kept = self.saved?.domains,
            Set(kept.map { $0.lowercased() }) != Set(sentDomains.map { $0.lowercased() })
        {
            notice =
                "Coolify kept the earlier domains. Its server may have no proxy, which domains need. Set one up in Coolify under the server's Proxy tab."
        }
    }

    private static func read(_ route: ResourceRoute, with client: CoolifyClient) async throws -> ResourceConfiguration {
        switch route {
        case .application(let uuid): ResourceConfiguration(application: try await client.application(uuid))
        case .database(let uuid): ResourceConfiguration(database: try await client.database(uuid))
        case .service(let uuid): ResourceConfiguration(service: try await client.service(uuid))
        }
    }

    private static func message(for error: Error) -> String {
        guard let error = error as? CoolifyError else { return error.localizedDescription }
        if error.isForbidden {
            return
                "This token can read settings but not change them. Give it write access in Coolify under Keys & Tokens."
        }
        return error.summary
    }
}

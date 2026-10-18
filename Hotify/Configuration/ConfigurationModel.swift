import CoolifyAPI
import Foundation

/// Loads and saves one resource's settings: its name and description, domains, health check, a database's
/// public port, an application's source, build, proxy labels, resource limits, and deployment commands, and a
/// service's compose file. Edits stay in `draft` until saved, across tab switches and the compose editor, since the
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
    var hasUnappliedChanges = false {
        didSet {
            if !hasUnappliedChanges { hasUnappliedCompose = false }
        }
    }
    /// Set with `hasUnappliedChanges` when the change was the compose file, which the containers run until a restart.
    private(set) var hasUnappliedCompose = false
    /// The compose file in Coolify changed after the user began editing theirs. Saving waits for them to pick one.
    private(set) var hasComposeConflict = false
    /// The compose file the user's edits started from, which tells their change from someone else's.
    private var composeBase: String?
    /// Set when the compose edits came back from an earlier visit, which the user may have forgotten.
    private(set) var restoredComposeEdits = false

    /// Compose edits not yet saved, by instance and service, so leaving the service does not lose them. In memory
    /// only: a compose file can hold passwords, so it is never written to disk.
    private static var composeStash: [String: StashedCompose] = [:]

    private struct StashedCompose {
        var base: String?
        var text: String
    }

    private var stashKey: String? {
        guard let client, let route else { return nil }
        return client.apiBaseURL.absoluteString + "|" + route.uuid
    }

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
        hasComposeConflict = false
        composeBase = nil
        restoredComposeEdits = false
    }

    /// Edits the compose file, and keeps the edit for when the user comes back to this service.
    func setCompose(_ text: String) {
        draft?.compose = text
        guard let stashKey else { return }
        Self.composeStash[stashKey] = text == saved?.compose ? nil : StashedCompose(base: composeBase, text: text)
    }

    /// Whether the compose file in `draft` differs from the one Coolify has.
    var hasComposeChanges: Bool {
        guard let compose = draft?.compose else { return false }
        return compose != saved?.compose
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
                composeBase = loaded.compose
                hasComposeConflict = false
                restore(onto: loaded, replacingEdits: replacingEdits)
            } else if draft?.compose == composeBase || draft?.compose == loaded.compose {
                // The edits leave the compose file alone, so it follows Coolify's. Kept as it was, the next save
                // would send the old file back over a newer one.
                draft?.compose = loaded.compose
                composeBase = loaded.compose
                hasComposeConflict = false
            } else if loaded.compose != composeBase {
                hasComposeConflict = true
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

    /// Puts back compose edits left from an earlier visit, unless the load follows a save, which used them up.
    private func restore(onto loaded: ResourceConfiguration, replacingEdits: Bool) {
        guard let stashKey else { return }
        guard !replacingEdits, let stashed = Self.composeStash[stashKey], loaded.compose != nil,
            stashed.text != loaded.compose
        else {
            Self.composeStash[stashKey] = nil
            return
        }
        draft?.compose = stashed.text
        composeBase = stashed.base
        restoredComposeEdits = true
        if loaded.compose != stashed.base { hasComposeConflict = true }
    }

    private func dropStashedCompose() {
        if let stashKey { Self.composeStash[stashKey] = nil }
        restoredComposeEdits = false
    }

    func revert() {
        draft = saved
        composeBase = saved?.compose
        hasComposeConflict = false
        saveError = nil
        conflicts = []
        dropStashedCompose()
    }

    /// Drops the user's compose edits for the file Coolify has now. Their other edits stay.
    func takeTheirCompose() {
        draft?.compose = saved?.compose
        composeBase = saved?.compose
        hasComposeConflict = false
        saveError = nil
        dropStashedCompose()
    }

    /// Sends what changed, then reads the resource back. `force` takes domains another resource already uses.
    /// `replacingTheirCompose` saves the compose file over one someone else changed in Coolify meanwhile.
    func save(force: Bool = false, replacingTheirCompose: Bool = false) async {
        guard let client, let route, draft != nil, saved != nil, !isSaving else { return }
        let generation = self.generation
        isSaving = true
        defer {
            if generation == self.generation { isSaving = false }
        }
        if replacingTheirCompose {
            hasComposeConflict = false
        } else if case .service = route, hasComposeChanges {
            // A compose file is replaced whole, so a change made in Coolify meanwhile would vanish without a word.
            // Reading first keeps the edits and raises `hasComposeConflict` if that happened.
            await load()
            guard generation == self.generation, !hasComposeConflict else { return }
        }
        guard let draft, let saved else { return }
        var sentDomains: [String]?
        var sentCompose = false
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
                sentCompose = update.dockerComposeRaw != nil
                _ = try await client.updateService(uuid, update)
                // Coolify writes a service's domains into its compose labels, which containers read as they start.
                // Nor does it restart for a new compose file. The containers run the old one until then.
                needsApply = update.urls != nil || sentCompose
            }
        } catch let error as CoolifyError where error.statusCode == 409 && !error.conflicts.isEmpty {
            guard generation == self.generation else { return }
            conflicts = error.conflicts
            saveError = nil
            // A service saves its name and compose file before it checks domains, so the reload shows what did stick.
            await load()
            if sentCompose, self.saved?.compose == draft.compose {
                hasUnappliedChanges = true
                hasUnappliedCompose = true
            }
            return
        } catch is CancellationError {
            return
        } catch {
            guard generation == self.generation else { return }
            saveError = (sentCompose ? ComposeFailure.message(for: error) : nil) ?? Self.message(for: error)
            return
        }
        guard generation == self.generation else { return }
        conflicts = []
        saveError = nil
        notice = nil
        if needsApply { hasUnappliedChanges = true }
        if sentCompose {
            hasUnappliedCompose = true
            dropStashedCompose()
        }
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

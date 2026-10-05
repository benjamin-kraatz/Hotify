import CoolifyAPI
import Foundation

/// The tags on one resource, and the team's tags to pick from. Adds and removals go to Coolify as they happen.
@Observable
final class ResourceTagsModel {
    private(set) var assigned: [Tag]
    private(set) var team: [Tag]
    var draft = ""
    private(set) var isLoading = false
    private(set) var isBusy = false
    private(set) var error: String?
    var pendingRemoval: Tag?

    private var client: CoolifyClient?
    private var route: ResourceRoute?
    private var generation = 0

    init(assigned: [Tag] = [], team: [Tag] = []) {
        self.assigned = assigned
        self.team = team
    }

    /// Team tags that are not already on this resource.
    var available: [Tag] {
        let taken = Set(assigned.map { $0.name.lowercased() })
        return team.filter { !taken.contains($0.name.lowercased()) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var canAddDraft: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 && !isBusy
    }

    /// Points later loads at this resource. A preview with no client keeps the tags it was given.
    func open(_ client: CoolifyClient?, route: ResourceRoute?) {
        guard client != nil else { return }
        let changed = self.route != route
        self.client = client
        self.route = route
        guard changed else { return }
        generation += 1
        assigned = []
        team = []
        draft = ""
        error = nil
        pendingRemoval = nil
    }

    func load() async {
        guard let client, let owner else { return }
        let ticket = generation
        if assigned.isEmpty, team.isEmpty { isLoading = true }
        defer {
            if ticket == generation { isLoading = false }
        }
        let resourceTask = Task { try await client.resourceTags(for: owner) }
        let teamTask = Task { try? await client.tags() }
        defer {
            resourceTask.cancel()
            teamTask.cancel()
        }
        do {
            let loaded = try await resourceTask.value
            guard ticket == generation else { return }
            assigned = loaded
            error = nil
        } catch is CancellationError {
            return
        } catch {
            guard ticket == generation else { return }
            self.error = Self.message(for: error)
        }
        if let loadedTeam = await teamTask.value, ticket == generation {
            team = loadedTeam
        }
    }

    func add(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, let client, let owner, !isBusy else { return }
        if assigned.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) { return }
        await perform {
            assigned = try await client.addTag(trimmed, to: owner)
        }
    }

    /// Creates a team tag when the name is new, then adds it here unless the create response already attached it.
    func addDraft() async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, let client, let owner, !isBusy else { return }
        if assigned.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            draft = ""
            return
        }
        if let existing = team.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            await add(name: existing.name)
            if error == nil { draft = "" }
            return
        }
        await perform {
            let created: TagCreation
            do {
                created = try await client.createTag(name: trimmed)
            } catch let error as CoolifyError where error.statusCode == 409 {
                assigned = try await client.addTag(trimmed, to: owner)
                draft = ""
                await reloadTeam(client)
                return
            }
            // POST /tags returns the team tag and does not attach it. A list means the tag is already on a resource.
            if created.isAttachedToResource {
                assigned = created.resourceTags
            } else {
                let name = created.tag.name.isEmpty ? trimmed : created.tag.name
                assigned = try await client.addTag(name, to: owner)
            }
            draft = ""
            await reloadTeam(client)
        }
    }

    func remove(_ tag: Tag) async {
        guard let client, let owner, !tag.uuid.isEmpty, !isBusy else { return }
        pendingRemoval = nil
        await perform {
            try await client.removeTag(tag.uuid, from: owner)
            assigned.removeAll { $0.uuid == tag.uuid }
        }
    }

    private func perform(_ work: () async throws -> Void) async {
        let ticket = generation
        isBusy = true
        defer {
            if ticket == generation { isBusy = false }
        }
        do {
            try await work()
            guard ticket == generation else { return }
            error = nil
        } catch is CancellationError {
            return
        } catch {
            guard ticket == generation else { return }
            self.error = Self.message(for: error)
        }
    }

    private func reloadTeam(_ client: CoolifyClient) async {
        if let loaded = try? await client.tags() {
            team = loaded
        }
    }

    private var owner: TagOwner? {
        switch route {
        case .application(let uuid): .application(uuid)
        case .database(let uuid): .database(uuid)
        case .service(let uuid): .service(uuid)
        case nil: nil
        }
    }

    private static func message(for error: Error) -> String {
        guard let error = error as? CoolifyError else { return error.localizedDescription }
        if error.isForbidden {
            return "This token can read tags but not change them. Give it write access in Coolify under Keys & Tokens."
        }
        return error.summary
    }
}

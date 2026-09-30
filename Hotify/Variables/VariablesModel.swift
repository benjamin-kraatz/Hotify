import CoolifyAPI
import Foundation

/// Loads and changes the environment variables of one resource.
@Observable
final class VariablesModel {
    var variables: [VariableLine] = []
    var loadError: String?
    /// A delete that failed. The editor shows its own save errors.
    var writeError: String?
    var isLoading = false
    /// Whether a load has finished for this resource, so an empty list means no variables rather than not yet.
    var hasLoaded = false
    /// Set after a change until the resource restarts or redeploys. Coolify hands variables to containers as they start.
    var hasUnappliedChanges = false
    var lastChangeWasPreview = false

    /// Which resource this model reads. The list reloads when it changes.
    private(set) var owner: EnvironmentVariableOwner?
    private var client: CoolifyClient?
    private var generation = 0

    /// Clears the previous resource and points later loads and writes at this one.
    func prepare(_ client: CoolifyClient, route: ResourceRoute) {
        generation += 1
        self.client = client
        owner = route.variableOwner
        variables = []
        hasLoaded = false
        loadError = nil
        writeError = nil
        hasUnappliedChanges = false
    }

    func load() async {
        guard let client, let owner else { return }
        let generation = self.generation
        if variables.isEmpty {
            isLoading = true
        }
        defer {
            if generation == self.generation {
                isLoading = false
            }
        }
        do {
            let loaded = try await client.environmentVariables(of: owner)
            guard generation == self.generation else { return }
            variables = loaded.map(VariableLine.init(variable:))
            hasLoaded = true
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == self.generation else { return }
            loadError = Self.message(for: error)
        }
    }

    /// Creates or updates a variable, then reloads. Throws a message the editor can show.
    func save(_ draft: EnvironmentVariableDraft, isNew: Bool) async throws {
        guard let client, let owner else { return }
        do {
            if isNew {
                _ = try await client.createEnvironmentVariable(draft, on: owner)
            } else {
                _ = try await client.updateEnvironmentVariable(draft, on: owner)
            }
        } catch {
            throw VariableWriteError(message: Self.message(for: error))
        }
        writeError = nil
        hasUnappliedChanges = true
        lastChangeWasPreview = draft.isPreview == true
        await load()
    }

    func delete(_ line: VariableLine) async {
        guard let client, let owner else { return }
        do {
            try await client.deleteEnvironmentVariable(line.id, from: owner)
            variables.removeAll { $0.id == line.id }
            writeError = nil
            hasUnappliedChanges = true
            lastChangeWasPreview = line.isPreview
        } catch {
            writeError = Self.message(for: error)
        }
        await load()
    }

    private static func message(for error: Error) -> String {
        (error as? CoolifyError)?.message ?? error.localizedDescription
    }
}

/// A failed create or update, worded for the editor.
struct VariableWriteError: Error, LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

extension ResourceRoute {
    var variableOwner: EnvironmentVariableOwner {
        switch self {
        case .application(let uuid): .application(uuid)
        case .database(let uuid): .database(uuid)
        case .service(let uuid): .service(uuid)
        }
    }
}

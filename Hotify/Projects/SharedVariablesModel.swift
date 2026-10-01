import CoolifyAPI
import Foundation

/// The shared variables of one scope: the project itself, or one of its environments.
struct SharedVariableSection: Identifiable, Hashable {
    var scope: SharedVariableScope
    /// `Project`, or the environment's name.
    var title: String
    var lines: [VariableLine] = []

    var id: SharedVariableScope { scope }

    /// How a resource's variable points at one of these, such as `{{project.API_URL}}`.
    func reference(to key: String) -> String {
        switch scope {
        case .project: "{{project.\(key)}}"
        case .environment: "{{environment.\(key)}}"
        }
    }
}

/// Loads and changes the variables a project and its environments share with their resources.
@Observable
final class SharedVariablesModel {
    private(set) var sections: [SharedVariableSection] = []
    var loadError: String?
    /// A delete that failed. The editor shows its own save errors.
    var writeError: String?
    /// Whether a load has finished, so an empty section means no variables rather than not yet.
    private(set) var hasLoaded = false
    /// Set after a change. Coolify fills a shared value into a resource when that resource is next deployed.
    var hasUnappliedChanges = false

    private var client: CoolifyClient?
    private var generation = 0

    init(sections: [SharedVariableSection] = [], hasLoaded: Bool = false) {
        self.sections = sections
        self.hasLoaded = hasLoaded
    }

    var isEmpty: Bool { sections.allSatisfy(\.lines.isEmpty) }

    /// Clears the previous project and points later loads and writes at this client. Call `track` next to say
    /// which project.
    func prepare(_ client: CoolifyClient) {
        generation += 1
        self.client = client
        sections = []
        hasLoaded = false
        loadError = nil
        writeError = nil
        hasUnappliedChanges = false
    }

    /// Lays out one section for the project and one per environment. A scope that was already there keeps its
    /// variables, so an environment being renamed or added does not blank the rest.
    func track(_ project: ProjectSummary) {
        let known = Dictionary(sections.map { ($0.scope, $0.lines) }) { first, _ in first }
        let scopes =
            [(SharedVariableScope.project(project.id), "Project")]
            + project.environments.map { environment in
                (
                    SharedVariableScope.environment(project: project.id, environment: environment.reference),
                    environment.name
                )
            }
        sections = scopes.map { scope, title in
            SharedVariableSection(scope: scope, title: title, lines: known[scope] ?? [])
        }
    }

    /// Loads every scope side by side. One that fails keeps what the last load found.
    func load() async {
        guard let client else { return }
        let generation = self.generation
        let scopes = sections.map(\.scope)

        let results = await withTaskGroup(of: ScopeResult.self) { group in
            for scope in scopes {
                group.addTask {
                    do {
                        return ScopeResult(scope: scope, variables: try await client.sharedVariables(in: scope))
                    } catch is CancellationError {
                        return ScopeResult(scope: scope)
                    } catch {
                        return ScopeResult(
                            scope: scope,
                            error: (error as? CoolifyError)?.message ?? error.localizedDescription
                        )
                    }
                }
            }
            var loaded: [ScopeResult] = []
            for await result in group {
                loaded.append(result)
            }
            return loaded
        }
        guard generation == self.generation, !Task.isCancelled else { return }

        for result in results {
            guard let variables = result.variables,
                let index = sections.firstIndex(where: { $0.scope == result.scope })
            else { continue }
            sections[index].lines = variables.map(VariableLine.init(shared:))
        }
        loadError = results.lazy.compactMap(\.error).first
        // A load that only failed has shown nothing yet, so the list keeps waiting rather than calling itself empty.
        hasLoaded = hasLoaded || results.contains { $0.variables != nil }
    }

    /// Creates or updates a variable, then reloads. Throws a message the editor can show.
    func save(_ draft: EnvironmentVariableDraft, replacing original: VariableLine?, in scope: SharedVariableScope)
        async throws
    {
        guard let client else { return }
        let shared = SharedVariableDraft(
            key: draft.key,
            value: draft.value,
            isLiteral: draft.isLiteral,
            isMultiline: draft.isMultiline,
            isShownOnce: draft.isShownOnce
        )
        do {
            if let original {
                guard let id = Int(original.id) else {
                    throw CoolifyError(message: "This variable has no id Coolify can address.")
                }
                _ = try await client.updateSharedVariable(id, with: shared, in: scope)
            } else {
                _ = try await client.createSharedVariable(shared, in: scope)
            }
        } catch {
            throw VariableWriteError(message: Self.message(for: error))
        }
        writeError = nil
        hasUnappliedChanges = true
        await load()
    }

    func delete(_ line: VariableLine, in scope: SharedVariableScope) async {
        guard let client, let id = Int(line.id) else { return }
        do {
            try await client.deleteSharedVariable(id, from: scope)
            if let index = sections.firstIndex(where: { $0.scope == scope }) {
                sections[index].lines.removeAll { $0.id == line.id }
            }
            writeError = nil
            hasUnappliedChanges = true
        } catch {
            writeError = Self.message(for: error)
        }
        await load()
    }

    /// Coolify answers a rejected field with "Validation failed." and the reason under `errors`, so this takes both.
    private static func message(for error: Error) -> String {
        (error as? CoolifyError)?.summary ?? error.localizedDescription
    }
}

extension VariableLine {
    init(shared variable: SharedVariable) {
        self.init(
            id: String(variable.id),
            key: variable.key,
            value: variable.value,
            isLiteral: variable.isLiteral,
            isMultiline: variable.isMultiline,
            isShownOnce: variable.isShownOnce
        )
        if let comment = variable.comment?.trimmingCharacters(in: .whitespacesAndNewlines), !comment.isEmpty {
            self.comment = comment
        }
    }
}

/// What one scope's request came back with. Both stay `nil` when it was cancelled.
nonisolated private struct ScopeResult: Sendable {
    var scope: SharedVariableScope
    var variables: [SharedVariable]?
    var error: String?
}

import CoolifyAPI
import Foundation

/// The projects and environments a resource can move into.
@Observable
final class MoveCatalog {
    var projects: [Project]
    var projectUUID: String?
    var environmentUUID: String?
    /// The environment the resource is in now. Moving there again does nothing.
    let currentEnvironmentUUID: String?
    var isLoading = false
    var hasLoaded: Bool
    var problem: String?

    private var client: CoolifyClient?

    init(
        projects: [Project] = [],
        projectUUID: String? = nil,
        environmentUUID: String? = nil,
        currentEnvironmentUUID: String? = nil
    ) {
        self.projects = projects
        self.projectUUID = projectUUID
        self.environmentUUID = environmentUUID
        self.currentEnvironmentUUID = currentEnvironmentUUID
        hasLoaded = !projects.isEmpty
    }

    var project: Project? { projects.first { $0.uuid == projectUUID } }

    var environments: [Environment] {
        (project?.environments ?? [])
            .filter { $0.uuid?.isEmpty == false }
            .sorted { lhs, rhs in
                let left = lhs.id ?? Int.max
                let right = rhs.id ?? Int.max
                if left != right { return left < right }
                return (lhs.name ?? "").localizedStandardCompare(rhs.name ?? "") == .orderedAscending
            }
    }

    var environment: Environment? { environments.first { $0.uuid == environmentUUID } }

    var environmentName: String {
        let name = environment?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "the new environment" : name
    }

    func prepare(_ client: CoolifyClient?) {
        self.client = client
    }

    func load() async {
        guard let client, !hasLoaded, !isLoading else { return }
        isLoading = true
        problem = nil
        defer { isLoading = false }
        do {
            let summaries = try await client.projects()
            // GET /projects omits environments. Only the project detail includes them.
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
            var byID: [String: Project] = [:]
            for project in summaries { byID[project.uuid] = project }
            for project in detailed { byID[project.uuid] = project }
            projects = byID.values.sorted {
                ($0.name ?? $0.uuid).localizedStandardCompare($1.name ?? $1.uuid) == .orderedAscending
            }
            // A failed detail leaves the list row, which has no environments, so there is nothing to move into.
            if detailed.isEmpty, !summaries.isEmpty, projects.allSatisfy({ ($0.environments ?? []).isEmpty }) {
                problem = "Environments didn't load."
                return
            }
            if projectUUID == nil || projects.contains(where: { $0.uuid == projectUUID }) == false {
                projectUUID =
                    projects.first {
                        $0.environments?.contains { $0.uuid == currentEnvironmentUUID } == true
                    }?.uuid ?? projects.first?.uuid
            }
            if environmentUUID == nil || environments.contains(where: { $0.uuid == environmentUUID }) == false {
                environmentUUID = Self.preferred(environments)?.uuid
            }
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            problem = placementFailure(error)
        }
    }

    func selectProject(_ uuid: String) {
        guard projectUUID != uuid else { return }
        projectUUID = uuid
        if let currentEnvironmentUUID, environments.contains(where: { $0.uuid == currentEnvironmentUUID }) {
            environmentUUID = currentEnvironmentUUID
        } else {
            environmentUUID = Self.preferred(environments)?.uuid
        }
    }

    func selectEnvironment(_ uuid: String) {
        environmentUUID = uuid
    }

    private static func preferred(_ environments: [Environment]) -> Environment? {
        environments.first { $0.name?.caseInsensitiveCompare("production") == .orderedSame } ?? environments.first
    }
}

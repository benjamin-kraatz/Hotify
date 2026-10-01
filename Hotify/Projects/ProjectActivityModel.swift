import CoolifyAPI
import Foundation

/// A production deployment on the project page, with the application it shipped.
struct ProjectDeployment: Identifiable, Hashable {
    var applicationUUID: String
    var applicationName: String
    /// Set when the project has several environments, where two applications often share a name.
    var environmentName: String?
    var line: DeploymentLine

    /// A deployment without a uuid falls back to its index, which repeats across applications.
    var id: String { "\(applicationUUID)/\(line.id)" }
    var application: ResourceRoute { .application(applicationUUID) }
}

/// One application's previews on the project page. Pull request numbers repeat across repositories, so previews
/// stay with their application.
struct ApplicationPreviews: Identifiable, Hashable {
    var application: ResourceRoute
    var name: String
    /// Set when the project has several environments, where two applications often share a name.
    var environmentName: String?
    /// `owner/repo`, when the application builds from github.com.
    var repository: String?
    var previews: [PreviewLine]

    var id: ResourceRoute { application }
}

/// The deployment history of every application in one project. Coolify has no route for a project's deployments
/// or previews, so this asks each application for its own.
@Observable
final class ProjectActivityModel {
    /// Newest first, by application uuid.
    private(set) var histories: [String: [DeploymentLine]] = [:]
    /// Whether a load has finished, so an empty history means nothing was deployed rather than not yet.
    private(set) var hasLoaded = false
    private(set) var loadError: String?
    /// The applications to ask, by uuid. The page keeps this current as the dashboard polls.
    var applications: [String] = []

    /// How far back each application's history is read. Enough for what shipped lately and the previews in use.
    static let historyLength = 30

    private var previewModels: [String: PreviewsModel] = [:]
    private var client: CoolifyClient?
    private var generation = 0

    init(histories: [String: [DeploymentLine]] = [:], hasLoaded: Bool = false) {
        self.histories = histories
        self.hasLoaded = hasLoaded
    }

    /// Clears the previous project and points later refreshes at this client.
    func prepare(_ client: CoolifyClient) {
        generation += 1
        self.client = client
        histories = [:]
        previewModels = [:]
        hasLoaded = false
        loadError = nil
    }

    /// Loads every application's history side by side. One that fails keeps what the last load found.
    func refresh() async {
        guard let client else { return }
        let generation = self.generation
        let applications = self.applications

        let take = Self.historyLength
        let results = await withTaskGroup(of: HistoryResult.self) { group in
            for uuid in applications {
                group.addTask {
                    do {
                        let page = try await client.applicationDeployments(uuid, take: take)
                        return HistoryResult(application: uuid, deployments: page.deployments)
                    } catch is CancellationError {
                        return HistoryResult(application: uuid)
                    } catch {
                        return HistoryResult(
                            application: uuid,
                            error: (error as? CoolifyError)?.message ?? error.localizedDescription
                        )
                    }
                }
            }
            var loaded: [HistoryResult] = []
            for await result in group {
                loaded.append(result)
            }
            return loaded
        }
        guard generation == self.generation else { return }
        // A cancelled load says nothing. Leaving the state alone keeps the page waiting rather than calling it empty.
        guard results.isEmpty || results.contains(where: { $0.deployments != nil || $0.error != nil }) else { return }

        var histories = self.histories.filter { applications.contains($0.key) }
        for result in results {
            guard let deployments = result.deployments else { continue }
            histories[result.application] = deployments.enumerated().map { index, deployment in
                DeploymentLine(deployment: deployment, fallbackID: "\(index)", clientAPIBaseURL: client.apiBaseURL)
            }
        }
        self.histories = histories
        loadError = results.lazy.compactMap(\.error).first
        hasLoaded = true
        await loadPreviewDetails(client, generation: generation)
    }

    /// Asks GitHub for titles and Coolify for the preview address, once per application, and only for one that
    /// has previews. Most have none, and GitHub allows few requests without a token.
    private func loadPreviewDetails(_ client: CoolifyClient, generation: Int) async {
        var fresh: [PreviewsModel] = []
        for (uuid, lines) in histories where previewModels[uuid] == nil && lines.contains(where: \.isPreview) {
            let model = PreviewsModel()
            model.prepare(client, route: .application(uuid))
            previewModels[uuid] = model
            fresh.append(model)
        }
        guard !fresh.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for model in fresh {
                group.addTask { await model.load() }
            }
        }
    }

    /// The newest production deployments across these applications of the project.
    func recentDeployments(
        of applications: [ResourceSummary], namesEnvironments: Bool, limit: Int = 6
    ) -> [ProjectDeployment] {
        applications
            .flatMap { application -> [ProjectDeployment] in
                guard case .application(let uuid) = application.route else { return [] }
                return (histories[uuid] ?? []).filter { !$0.isPreview }.map { line in
                    ProjectDeployment(
                        applicationUUID: uuid,
                        applicationName: application.name,
                        environmentName: namesEnvironments ? application.place?.environmentName : nil,
                        line: line
                    )
                }
            }
            .sorted { ($0.line.startedAt ?? .distantPast) > ($1.line.startedAt ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }

    /// Each application's previews, for the applications that have any, in the order given.
    func previews(for applications: [ResourceSummary], namesEnvironments: Bool) -> [ApplicationPreviews] {
        applications.compactMap { application in
            guard case .application(let uuid) = application.route, let history = histories[uuid] else { return nil }
            let model = previewModels[uuid]
            let previews = model?.previews(from: history) ?? PreviewLine.group(history)
            guard !previews.isEmpty else { return nil }
            return ApplicationPreviews(
                application: application.route,
                name: application.name,
                environmentName: namesEnvironments ? application.place?.environmentName : nil,
                repository: model?.repository?.label,
                previews: previews
            )
        }
    }

    /// The pull request on GitHub, when the application builds from github.com.
    func gitHubURL(for application: ResourceRoute, number: Int) -> URL? {
        guard case .application(let uuid) = application else { return nil }
        return previewModels[uuid]?.gitHubURL(for: number)
    }

    /// What is known of one application's history, to show the moment its screen opens.
    func history(for application: ResourceRoute) -> [DeploymentLine] {
        guard case .application(let uuid) = application else { return [] }
        return histories[uuid] ?? []
    }
}

/// What one application's request came back with. Both stay `nil` when it was cancelled.
nonisolated private struct HistoryResult: Sendable {
    var application: String
    var deployments: [Deployment]?
    var error: String?
}

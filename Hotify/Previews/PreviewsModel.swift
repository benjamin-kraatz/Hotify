import CoolifyAPI
import Foundation

/// An application's previews: what GitHub and Coolify's settings add to the history, and the actions on one preview.
@MainActor @Observable
final class PreviewsModel {
    var repository: GitHubRepository?
    /// Open PRs from GitHub's first page, by number. Empty for a repository off github.com or out of reach.
    var pullRequests: [Int: GitHubPullRequest] = [:]
    var application: Application?
    var actionError: String?
    /// Builds Hotify started that the history may not list yet.
    private(set) var queued: [DeploymentLine] = []
    /// When each preview was removed from Hotify, for this session.
    private(set) var removed: [Int: Date] = [:]
    private(set) var work: [Int: PreviewWork] = [:]

    private var client: CoolifyClient?
    private var applicationUUID: String?
    private var generation = 0

    init(
        application: Application? = nil, repository: GitHubRepository? = nil,
        pullRequests: [GitHubPullRequest] = []
    ) {
        self.application = application
        self.repository = repository
        self.pullRequests = Dictionary(pullRequests.map { ($0.number, $0) }) { first, _ in first }
    }

    /// Clears the previous application. Only applications have previews, so any other route leaves this empty.
    func prepare(_ client: CoolifyClient, route: ResourceRoute) {
        generation += 1
        self.client = client
        guard case .application(let uuid) = route else {
            applicationUUID = nil
            return
        }
        applicationUUID = uuid
        application = nil
        repository = nil
        pullRequests = [:]
        queued = []
        removed = [:]
        work = [:]
        actionError = nil
    }

    /// Loads the application for its preview address and repository, then the repository's open PRs for titles.
    /// The previews still show without either, by number and commit.
    func load() async {
        guard let client, let applicationUUID else { return }
        let generation = generation
        guard let loaded = try? await client.application(applicationUUID), generation == self.generation else { return }
        application = loaded
        repository = try? GitHubRepository(loaded.gitRepository ?? "")
        guard let repository else { return }
        let prs = try? await GitHubPullRequestClient().pullRequests(
            repository: repository, token: GitHubCredentialStore.load())
        guard generation == self.generation, let prs else { return }
        pullRequests = Dictionary(prs.map { ($0.number, $0) }) { first, _ in first }
    }

    /// Previews from the history, with what this model knows added.
    func previews(from deployments: [DeploymentLine]) -> [PreviewLine] {
        PreviewLine.group(deployments, queued: queued, removed: removed).map { preview in
            var preview = preview
            if let pr = pullRequests[preview.number] {
                preview.title = pr.title
                preview.branch = pr.head.ref
                preview.isDraft = pr.draft
            }
            preview.url = application?.previewURL(pullRequest: preview.number)
            preview.work = work[preview.number]
            return preview
        }
    }

    /// The pull request on GitHub, when the application builds from github.com.
    func gitHubURL(for number: Int) -> URL? {
        repository.flatMap { URL(string: "https://github.com/\($0.owner)/\($0.name)/pull/\(number)") }
    }

    /// Records a build the deploy sheet queued, and returns the line to follow it by.
    @discardableResult
    func noteQueued(_ deployment: QueuedDeployment, number: Int) -> DeploymentLine {
        let line = DeploymentLine(
            id: deployment.deploymentUUID ?? UUID().uuidString,
            status: "queued",
            pullRequest: number,
            startedAt: .now
        )
        queued.removeAll { $0.pullRequest == number }
        queued.append(line)
        removed[number] = nil
        return line
    }

    /// Builds the PR's preview again. Returns the queued build, or `nil` when Coolify refused it.
    func redeploy(_ number: Int) async -> DeploymentLine? {
        guard let client, let applicationUUID, work[number] == nil else { return nil }
        let generation = generation
        work[number] = .redeploying
        actionError = nil
        defer { if generation == self.generation { work[number] = nil } }
        do {
            let result = try await client.deployPreview(applicationUUID: applicationUUID, pullRequestID: number)
            LocalActions.note(.deployment, .application(applicationUUID))
            guard generation == self.generation,
                let queued = result.deployments.first(where: { $0.resourceUUID == applicationUUID })
            else { return nil }
            return noteQueued(queued, number: number)
        } catch {
            guard generation == self.generation else { return nil }
            actionError = Self.message(for: error, number: number)
            return nil
        }
    }

    /// Stops a running preview build. The preview keeps what it ran before.
    func cancel(_ deployment: DeploymentLine) async {
        guard let client, let number = deployment.pullRequest, work[number] == nil else { return }
        let generation = generation
        actionError = nil
        do {
            _ = try await client.cancelDeployment(deployment.id)
            if generation == self.generation {
                queued.removeAll { $0.id == deployment.id }
            }
        } catch {
            guard generation == self.generation else { return }
            actionError = Self.message(for: error, number: number)
        }
    }

    /// Asks Coolify to tear the preview down: its containers, volumes, and record. The history stays.
    func remove(_ number: Int) async {
        guard let client, let applicationUUID, work[number] == nil else { return }
        let generation = generation
        work[number] = .removing
        actionError = nil
        defer { if generation == self.generation { work[number] = nil } }
        do {
            _ = try await client.deletePreview(applicationUUID: applicationUUID, pullRequestID: number)
            guard generation == self.generation else { return }
            queued.removeAll { $0.pullRequest == number }
            removed[number] = .now
        } catch {
            guard generation == self.generation else { return }
            actionError = Self.message(for: error, number: number)
        }
    }

    private static func message(for error: Error, number: Int) -> String {
        let reason = (error as? CoolifyError)?.message ?? error.localizedDescription
        return "PR #\(number): \(reason)"
    }
}

import CoolifyAPI
import Foundation

/// Loads PR choices on demand and queues a preview without touching production actions.
@MainActor @Observable
final class PreviewDeploymentModel {
    var choices: [PreviewChoice] = []
    var repository: GitHubRepository?
    var isLoading = false
    var isDeploying = false
    var loadError: String?
    var deployError: String?
    var nextPage: Int?
    var setupURL: URL?
    private var generation = 0

    func load(
        client: CoolifyClient, application: String, token: String?, previews: [PreviewLine] = [], more: Bool = false
    ) async {
        generation += 1
        let generation = generation
        isLoading = true
        loadError = nil
        setupURL = client.apiBaseURL.deletingLastPathComponent().deletingLastPathComponent()
        defer { if generation == self.generation { isLoading = false } }
        do {
            let page = more ? (nextPage ?? 1) : 1
            if !more {
                // Reuse the detail screen's history; fetching it again can include large build logs.
                choices = previews.filter { $0.number > 0 }.sorted { $0.number > $1.number }.map { preview in
                    PreviewChoice(
                        number: preview.number, title: preview.title, branch: preview.branch, isDraft: preview.isDraft,
                        state: preview.state, commitMessage: preview.latest.message)
                }
                repository = nil
                nextPage = nil
                let info = try await client.application(application)
                try Task.checkCancellation()
                guard generation == self.generation else { return }
                repository = try? GitHubRepository(info.gitRepository ?? "")
            }
            guard let repository else {
                loadError = "Open PRs can be loaded from github.com. You can still deploy a preview by its PR number."
                return
            }
            let prs = try await GitHubPullRequestClient().pullRequests(repository: repository, token: token, page: page)
            try Task.checkCancellation()
            guard generation == self.generation else { return }
            for pr in prs where pr.number > 0 {
                if let index = choices.firstIndex(where: { $0.number == pr.number }) {
                    choices[index].title = pr.title
                    choices[index].branch = pr.head.ref
                    choices[index].isDraft = pr.draft
                } else {
                    choices.append(
                        PreviewChoice(number: pr.number, title: pr.title, branch: pr.head.ref, isDraft: pr.draft))
                }
            }
            choices.sort { $0.number > $1.number }
            nextPage = prs.count == 50 ? page + 1 : nil
        } catch {
            guard generation == self.generation, !Task.isCancelled else { return }
            loadError = (error as? CoolifyError)?.message ?? error.localizedDescription
        }
    }

    func deploy(client: CoolifyClient, application: String, number: Int) async -> QueuedDeployment? {
        guard !isDeploying, number > 0 else { return nil }
        isDeploying = true
        deployError = nil
        defer { isDeploying = false }
        do {
            let result = try await client.deployPreview(applicationUUID: application, pullRequestID: number)
            LocalActions.note(.deployment, .application(application))
            return result.deployments.first { $0.resourceUUID == application && !($0.deploymentUUID ?? "").isEmpty }
        } catch {
            deployError = (error as? CoolifyError)?.message ?? error.localizedDescription
            return nil
        }
    }
}

/// A PR enriched with any preview found in recent deployment history.
struct PreviewChoice: Identifiable {
    var number: Int
    var title: String?
    var branch: String?
    var isDraft = false
    /// Where its preview stands. `nil` for a PR with no preview in the recent history.
    var state: PreviewState?
    /// The subject of the commit its preview last built, until GitHub names the PR.
    var commitMessage: String?
    var id: Int { number }

    var headline: String {
        title ?? commitMessage ?? "Pull request #\(number)"
    }
}

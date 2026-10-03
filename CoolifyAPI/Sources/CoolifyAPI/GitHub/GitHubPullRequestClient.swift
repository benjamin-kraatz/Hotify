import Foundation

/// Loads PRs from GitHub independently of the Coolify client and its credentials.
public struct GitHubPullRequestClient: Sendable {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        self.session = session ?? CoolifyClient.makeSession()
    }

    /// One page of open PRs, newest first. A token is optional for public repositories.
    public func pullRequests(repository: GitHubRepository, token: String? = nil, page: Int = 1) async throws
        -> [GitHubPullRequest]
    {
        try await GitHubRequest.get(
            [GitHubPullRequest].self,
            path: "/repos/\(repository.owner)/\(repository.name)/pulls",
            query: [
                URLQueryItem(name: "state", value: "open"),
                URLQueryItem(name: "sort", value: "created"),
                URLQueryItem(name: "direction", value: "desc"),
                URLQueryItem(name: "per_page", value: "50"),
                URLQueryItem(name: "page", value: String(max(1, page))),
            ],
            token: token,
            session: session,
            subject: "pull requests"
        )
    }
}

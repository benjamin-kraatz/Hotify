import Foundation

/// Loads a branch's commits from GitHub independently of the Coolify client and its credentials.
public struct GitHubCommitClient: Sendable {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        self.session = session ?? CoolifyClient.makeSession()
    }

    /// One page of a branch's commits, newest first. A token is optional for public repositories. Without one,
    /// GitHub allows 60 requests an hour, so load this when someone looks, not on a timer.
    public func commits(repository: GitHubRepository, branch: String, token: String? = nil, page: Int = 1)
        async throws -> [GitHubCommit]
    {
        try await GitHubRequest.get(
            [GitHubCommit].self,
            path: "/repos/\(repository.owner)/\(repository.name)/commits",
            query: [
                URLQueryItem(name: "sha", value: branch),
                URLQueryItem(name: "per_page", value: "30"),
                URLQueryItem(name: "page", value: String(max(1, page))),
            ],
            token: token,
            session: session,
            subject: "commits",
            // GitHub answers 404 for a branch it doesn't have, too.
            notFound:
                "GitHub has no branch \(branch) in this repository, or can't see the repository. For a private one, connect a token with read access to its contents."
        )
    }
}

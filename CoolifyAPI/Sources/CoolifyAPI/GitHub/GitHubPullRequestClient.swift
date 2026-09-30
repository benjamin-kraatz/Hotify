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
        let path = "https://api.github.com/repos/\(repository.owner)/\(repository.name)/pulls"
        var components = URLComponents(string: path)!
        components.queryItems = [
            URLQueryItem(name: "state", value: "open"),
            URLQueryItem(name: "sort", value: "created"),
            URLQueryItem(name: "direction", value: "desc"),
            URLQueryItem(name: "per_page", value: "50"),
            URLQueryItem(name: "page", value: String(max(1, page))),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request, delegate: GitHubRedirectPolicy())
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else {
            let message: String
            switch response.statusCode {
            case 401: message = "GitHub rejected the token. Check its access to this repository."
            case 404:
                message =
                    "GitHub couldn't find this repository. For a private repository, connect a token with read access to pull requests."
            case 403, 429:
                message =
                    "GitHub denied access or its rate limit was reached. Check your token's repository access or try again later."
            default: message = "GitHub couldn't load pull requests. Try again later."
            }
            throw CoolifyError(statusCode: response.statusCode, message: message)
        }
        return try JSONDecoder().decode([GitHubPullRequest].self, from: data)
    }
}

/// Follows repository renames only within GitHub's HTTPS API origin.
final class GitHubRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard Self.permits(request.url) else {
            completionHandler(nil)
            return
        }
        var redirected = request
        redirected.setValue(
            task.originalRequest?.value(forHTTPHeaderField: "Authorization"), forHTTPHeaderField: "Authorization")
        completionHandler(redirected)
    }

    static func permits(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme?.lowercased() == "https" && url.host?.lowercased() == "api.github.com"
            && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
    }
}

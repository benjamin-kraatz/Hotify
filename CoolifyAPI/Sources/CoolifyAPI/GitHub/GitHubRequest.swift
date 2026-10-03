import Foundation

/// One GET to GitHub's API, with the headers it expects, an optional token, and errors worded for a person. GitHub's
/// own error text stays out of them, since it can echo what was sent.
enum GitHubRequest {
    /// `subject` names what is loading, such as "pull requests", for the error messages. `notFound` replaces the 404
    /// message, for a request that can also miss on something other than the repository.
    static func get<T: Decodable>(
        _ type: T.Type,
        path: String,
        query: [URLQueryItem],
        token: String?,
        session: URLSession,
        subject: String,
        notFound: String? = nil
    ) async throws -> T {
        var components = URLComponents(string: "https://api.github.com\(path)")!
        components.queryItems = query
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
                    notFound
                    ?? "GitHub couldn't find this repository. For a private repository, connect a token with read access to its \(subject)."
            case 403, 429:
                message =
                    "GitHub denied access or its rate limit was reached. Check your token's repository access or try again later."
            default: message = "GitHub couldn't load \(subject). Try again later."
            }
            throw CoolifyError(statusCode: response.statusCode, message: message)
        }
        return try JSONDecoder().decode(T.self, from: data)
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

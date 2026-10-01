import Foundation

/// A link to GitHub's form for a new fine-grained token, filled in with what the PR picker needs and nothing more.
///
/// It leaves the resource owner out on purpose. GitHub's `target_name` only changes what the owner menu shows, and the
/// token is still made for the personal account. Picking the owner by hand also drops the pre-filled permissions.
enum GitHubTokenTemplate {
    static let expiryDays = 90

    static func url(createdOn date: Date = .now) -> URL {
        var components = URLComponents(string: "https://github.com/settings/personal-access-tokens/new")!
        components.queryItems = [
            // Token names are unique per account, so the date keeps a second token from clashing with the first.
            URLQueryItem(name: "name", value: "Hotify \(date.formatted(.iso8601.year().month().day()))"),
            URLQueryItem(
                name: "description",
                value: "Lets Hotify list open pull requests when it deploys Coolify previews. Read-only."
            ),
            URLQueryItem(name: "expires_in", value: String(expiryDays)),
            URLQueryItem(name: "pull_requests", value: "read"),
        ]
        return components.url!
    }

    /// Fine-grained tokens start `github_pat_`. Classic ones start `ghp_` and also work.
    static func looksLikeToken(_ text: String) -> Bool {
        text.hasPrefix("github_pat_") || text.hasPrefix("ghp_")
    }
}

import Foundation

/// An open GitHub pull request, including its source branch and draft status.
public struct GitHubPullRequest: Decodable, Identifiable, Sendable, Hashable {
    public var number: Int
    public var title: String
    public var draft: Bool
    public var head: Branch
    public var id: Int { number }

    /// The source branch of a pull request.
    public struct Branch: Decodable, Sendable, Hashable {
        public var ref: String
    }
}

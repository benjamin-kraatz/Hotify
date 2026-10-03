import Foundation

/// One commit on a GitHub branch: its SHA, message, author, and when it was made.
public struct GitHubCommit: Decodable, Identifiable, Sendable, Hashable {
    public var sha: String
    public var message: String
    public var authorName: String?
    /// The GitHub account, when the author has one. GitHub leaves it out for an email it doesn't know.
    public var authorLogin: String?
    public var date: Date?

    public var id: String { sha }
    public var shortSHA: String { String(sha.prefix(7)) }
    /// The first line of the message.
    public var subject: String { message.components(separatedBy: .newlines).first ?? message }

    public init(sha: String, message: String, authorName: String? = nil, authorLogin: String? = nil, date: Date? = nil)
    {
        self.sha = sha
        self.message = message
        self.authorName = authorName
        self.authorLogin = authorLogin
        self.date = date
    }

    enum CodingKeys: String, CodingKey { case sha, commit, author }
    private struct Details: Decodable {
        var message: String
        var author: Person?
    }
    private struct Person: Decodable {
        var name: String?
        var date: String?
    }
    private struct Account: Decodable { var login: String? }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sha = try container.decode(String.self, forKey: .sha)
        let details = try container.decode(Details.self, forKey: .commit)
        message = details.message
        authorName = details.author?.name
        date = details.author?.date.flatMap(CoolifyTimestamp.parse)
        authorLogin = (try? container.decodeIfPresent(Account.self, forKey: .author))?.login
    }
}

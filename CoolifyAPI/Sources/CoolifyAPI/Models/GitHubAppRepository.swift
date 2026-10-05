import Foundation

/// A repository a Coolify GitHub App can see. `fullName` is `owner/name`, which is what creating an application sends.
public struct GitHubAppRepository: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int?
    public var name: String
    /// `owner/name`.
    public var fullName: String
    public var isPrivate: Bool?
    public var htmlURL: String?
    public var defaultBranch: String?

    /// The owner segment of `fullName`.
    public var owner: String {
        let parts = fullName.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        return parts.count == 2 ? String(parts[0]) : ""
    }

    /// The repository segment of `fullName`.
    public var repositoryName: String {
        let parts = fullName.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        return parts.count == 2 ? String(parts[1]) : name
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName
        case isPrivate = "private"
        case htmlURL = "htmlUrl"
        case defaultBranch
        case owner
    }

    public init(
        id: Int? = nil,
        name: String,
        fullName: String,
        isPrivate: Bool? = nil,
        htmlURL: String? = nil,
        defaultBranch: String? = nil
    ) {
        self.id = id
        self.name = name
        self.fullName = fullName
        self.isPrivate = isPrivate
        self.htmlURL = htmlURL
        self.defaultBranch = defaultBranch
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.flexInt(.id)
        name = container.flexString(.name) ?? ""
        let owner = try? container.decodeIfPresent(Owner.self, forKey: .owner)
        if let fullName = container.flexString(.fullName), !fullName.isEmpty {
            self.fullName = fullName
        } else if let login = owner?.login, !login.isEmpty, !name.isEmpty {
            fullName = "\(login)/\(name)"
        } else {
            fullName = name
        }
        isPrivate = container.flexBool(.isPrivate)
        htmlURL = container.flexString(.htmlURL)
        defaultBranch = container.flexString(.defaultBranch)
    }
}

private struct Owner: Decodable {
    var login: String?

    enum CodingKeys: String, CodingKey {
        case login
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        login = container.flexString(.login)
    }
}

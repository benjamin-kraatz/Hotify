import Foundation

/// The team bound to one API token.
public struct Team: Decodable, Sendable, Hashable {
    public var id: Int?
    public var name: String
    public var personalTeam: Bool?

    public init(id: Int? = nil, name: String, personalTeam: Bool? = nil) {
        self.id = id
        self.name = name
        self.personalTeam = personalTeam
    }
}

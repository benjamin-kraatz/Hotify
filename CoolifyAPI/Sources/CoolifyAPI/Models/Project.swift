import Foundation

/// A Coolify project. `GET /projects/{uuid}` includes its environments; the list endpoint may not.
public struct Project: Decodable, Sendable, Hashable {
    public var id: Int?
    public var uuid: String
    public var name: String?
    public var description: String?
    public var environments: [Environment]?
}

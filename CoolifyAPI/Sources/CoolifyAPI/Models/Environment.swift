import Foundation

/// An environment inside a project. Coolify's OpenAPI schema omits `uuid`; the live record has one.
public struct Environment: Decodable, Sendable, Hashable {
    public var id: Int?
    public var uuid: String?
    public var name: String?
    public var description: String?
}

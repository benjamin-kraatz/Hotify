import Foundation

/// The uuid Coolify returns after it creates a project or an environment.
public struct CreatedResource: Decodable, Sendable, Hashable {
    public var uuid: String
}

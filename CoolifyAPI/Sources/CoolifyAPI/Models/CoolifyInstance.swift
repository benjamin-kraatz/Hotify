import Foundation

/// A saved Coolify instance. The API token stays in the Keychain, not in this value.
public struct CoolifyInstance: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var baseURL: URL

    public init(id: UUID = UUID(), name: String, baseURL: URL) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
    }

    public func client(token: String) throws -> CoolifyClient {
        try CoolifyClient(instanceURL: baseURL, token: token)
    }
}

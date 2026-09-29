import Foundation

/// A standalone database. Containers that belong to a service stay on `Service`.
public struct Database: Decodable, Sendable, Identifiable, Hashable, HasResourceStatus {
    public var uuid: String
    public var name: String?
    public var status: String?

    public var id: String { uuid }
}

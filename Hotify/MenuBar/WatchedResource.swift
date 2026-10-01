import Foundation

/// A menu bar selection. Only resource identifiers and display names are persisted.
struct WatchedResource: Codable, Identifiable, Hashable {
    var instanceID: UUID
    var instanceName: String
    var uuid: String
    var kind: String
    var name: String
    var id: String { "\(instanceID.uuidString)/\(kind)/\(uuid)" }

    init(instanceID: UUID, instanceName: String, resource: ResourceSummary) {
        self.instanceID = instanceID
        self.instanceName = instanceName
        name = resource.name
        uuid = resource.route.uuid
        kind = resource.route.key
    }

    var route: ResourceRoute? { ResourceRoute(key: kind, uuid: uuid) }
}

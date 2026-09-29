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
        switch resource.route {
        case .application(let uuid):
            self.uuid = uuid
            kind = "application"
        case .database(let uuid):
            self.uuid = uuid
            kind = "database"
        case .service(let uuid):
            self.uuid = uuid
            kind = "service"
        }
    }

    var route: ResourceRoute? {
        switch kind {
        case "application": .application(uuid)
        case "database": .database(uuid)
        case "service": .service(uuid)
        default: nil
        }
    }
}

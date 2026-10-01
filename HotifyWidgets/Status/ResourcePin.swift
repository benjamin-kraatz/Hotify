import Foundation

/// One resource a widget or control points at: the instance it lives on and its route.
struct ResourcePin: Hashable, Identifiable {
    var instanceID: UUID
    var route: ResourceRoute

    /// `<instance>/<kind>/<uuid>`, the same shape the menu bar saves.
    var id: String { "\(instanceID.uuidString)/\(route.key)/\(route.uuid)" }

    var link: URL { ResourceLink(instanceID: instanceID, route: route).url }

    init(instanceID: UUID, route: ResourceRoute) {
        self.instanceID = instanceID
        self.route = route
    }

    init?(id: String) {
        let parts = id.split(separator: "/", maxSplits: 2).map(String.init)
        guard parts.count == 3, let instanceID = UUID(uuidString: parts[0]),
            let route = ResourceRoute(key: parts[1], uuid: parts[2])
        else { return nil }
        self.init(instanceID: instanceID, route: route)
    }
}

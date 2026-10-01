import Foundation

/// A link that opens one resource in Hotify: `hotify://resource/<instance>/<kind>/<uuid>`.
struct ResourceLink: Hashable {
    var instanceID: UUID
    var route: ResourceRoute

    static let scheme = "hotify"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "resource"
        components.path = "/\(instanceID.uuidString)/\(route.key)/\(route.uuid)"
        return components.url ?? URL(string: "\(Self.scheme)://")!
    }

    init(instanceID: UUID, route: ResourceRoute) {
        self.instanceID = instanceID
        self.route = route
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme, url.host() == "resource" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 3, let instanceID = UUID(uuidString: parts[0]),
            let route = ResourceRoute(key: parts[1], uuid: parts[2])
        else { return nil }
        self.init(instanceID: instanceID, route: route)
    }
}

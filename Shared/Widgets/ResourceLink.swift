import Foundation

/// A link that opens one resource in Hotify: `hotify://resource/<instance>/<kind>/<uuid>`, with `?open=` for a
/// place inside it, such as `?open=preview&pr=12`.
struct ResourceLink: Hashable {
    var instanceID: UUID
    var route: ResourceRoute
    var place: Place?

    /// Where in the resource the link opens. Without one, it opens at its front.
    enum Place: Hashable {
        case deployments
        /// One pull request's preview.
        case preview(Int)
        /// A database's backups.
        case backups
    }

    static let scheme = "hotify"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "resource"
        components.path = "/\(instanceID.uuidString)/\(route.key)/\(route.uuid)"
        switch place {
        case .deployments:
            components.queryItems = [URLQueryItem(name: "open", value: "deployments")]
        case .preview(let pullRequest):
            components.queryItems = [
                URLQueryItem(name: "open", value: "preview"), URLQueryItem(name: "pr", value: String(pullRequest)),
            ]
        case .backups:
            components.queryItems = [URLQueryItem(name: "open", value: "backups")]
        case nil:
            break
        }
        return components.url ?? URL(string: "\(Self.scheme)://")!
    }

    init(instanceID: UUID, route: ResourceRoute, place: Place? = nil) {
        self.instanceID = instanceID
        self.route = route
        self.place = place
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme, url.host() == "resource" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 3, let instanceID = UUID(uuidString: parts[0]),
            let route = ResourceRoute(key: parts[1], uuid: parts[2])
        else { return nil }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in query.first { $0.name == name }?.value }
        let place: Place? =
            switch value("open") {
            case "deployments": .deployments
            case "preview": value("pr").flatMap(Int.init).map(Place.preview)
            case "backups": .backups
            default: nil
            }
        self.init(instanceID: instanceID, route: route, place: place)
    }
}

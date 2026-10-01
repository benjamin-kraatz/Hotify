import Foundation

/// What the detail column shows: one resource, or the project a group of them belongs to.
enum DetailRoute: Hashable {
    case resource(ResourceRoute)
    /// A project, by its uuid.
    case project(String)
}

/// Where a resource opens when something other than its list row leads there, such as a card on the project page.
struct ResourceEntry: Hashable {
    enum Place: Hashable {
        /// Its deployment history.
        case deployments
        /// Its previews space: the board, or one pull request.
        case previews(PreviewPlace)
    }

    var place: Place
    /// History the caller already loaded. It shows at once, until the resource's own request answers.
    var history: [DeploymentLine] = []
}

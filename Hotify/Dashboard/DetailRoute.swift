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
        /// A database's backups.
        case backups
        /// One deployment, and whether to ask Apple Intelligence about it at once.
        case deployment(String, explains: Bool)
        /// The confirmation to roll back to the newest earlier image.
        case rollback
    }

    var place: Place
    /// History the caller already loaded. It shows at once, until the resource's own request answers.
    var history: [DeploymentLine] = []
}

extension ResourceEntry {
    /// The place a widget's link points at.
    init(_ place: ResourceLink.Place) {
        switch place {
        case .deployments: self.init(place: .deployments)
        case .preview(let pullRequest): self.init(place: .previews(.preview(pullRequest)))
        case .backups: self.init(place: .backups)
        case .deployment(let id, let explains): self.init(place: .deployment(id, explains: explains))
        case .rollback: self.init(place: .rollback)
        }
    }
}

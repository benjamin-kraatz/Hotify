import Foundation

/// One notification to post: what happened, where it opens, and the instance it belongs to.
struct Notice: Hashable {
    var instanceID: UUID
    var event: NotificationEvent
    /// The resource or server it is about.
    var title: String
    /// The project and environment, when known.
    var subtitle: String?
    var body: String
    /// Where a click opens. `nil` opens the instance.
    var link: URL?
    /// Where Explain opens a failed deployment, and asks Apple Intelligence about it.
    var explainLink: URL?
    /// Where Roll Back opens the confirmation.
    var rollbackLink: URL?
    /// The resource it is about. `nil` for a server.
    var route: ResourceRoute?
    var place: ResourcePlace?
    /// The deployment that ended, for a deploy's notice.
    var deploymentID: String?
    /// The pull request a preview's deploy built. 0 for production.
    var pullRequest = 0
    var commit: String?
    var commitMessage: String?
    /// Names this one change, so a Shortcut runs once for it however it is seen again.
    var eventKey: String?
    /// Failures and outages break through Focus where it allows that. A finished deploy doesn't.
    var isTimeSensitive: Bool { event != .deploymentFinished && event != .deploymentFinishedElsewhere }
}

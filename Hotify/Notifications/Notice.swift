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
    /// Failures and outages break through Focus where it allows that. A finished deploy doesn't.
    var isTimeSensitive: Bool { event != .deploymentFinished && event != .deploymentFinishedElsewhere }
}

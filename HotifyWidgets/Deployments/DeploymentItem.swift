import CoolifyAPI
import Foundation

/// One deployment as a widget lists it. A preview carries its pull request and burns blue.
struct DeploymentItem: Codable, Hashable, Identifiable {
    var id: String
    /// The application's `ResourcePin` id.
    var pinID: String
    var applicationName: String
    var instanceName: String
    var status: String
    var commit: String?
    var message: String?
    var pullRequest: Int?
    var isRestart = false
    var startedAt: Date?
    var finishedAt: Date?

    var heat: Heat { DeploymentStatus.heat(status) }
    var statusLabel: String { DeploymentStatus.label(status) }
    var isUnderway: Bool { DeploymentStatus.isUnderway(status) }
    var tone: FlameTone { pullRequest == nil ? .production : .preview }

    /// When it ended, or when it started while it still runs.
    var shownDate: Date? { isUnderway ? startedAt : (finishedAt ?? startedAt) }

    /// The commit's subject, else what kind of deploy it was.
    var summary: String {
        if let message { return message }
        if isRestart { return "Restart" }
        if let commit { return "Commit \(commit)" }
        return "Manual deploy"
    }

    /// Opens the application's deployments, or the preview a preview deploy built.
    var link: URL? {
        guard let pin = ResourcePin(id: pinID) else { return nil }
        let place: ResourceLink.Place = pullRequest.map(ResourceLink.Place.preview) ?? .deployments
        return ResourceLink(instanceID: pin.instanceID, route: pin.route, place: place).url
    }

    init(_ deployment: Deployment, pinID: String, applicationName: String, instanceName: String) {
        id = deployment.deploymentUUID.isEmpty ? "\(pinID)/\(deployment.createdAt ?? "")" : deployment.deploymentUUID
        self.pinID = pinID
        self.applicationName = applicationName
        self.instanceName = instanceName
        status = deployment.status ?? "unknown"
        if let commit = deployment.commit, !commit.isEmpty, commit != "HEAD" {
            self.commit = String(commit.prefix(7))
        }
        if let message = deployment.commitMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            // Only the subject line.
            self.message = message.components(separatedBy: .newlines).first
        }
        pullRequest = deployment.isPreview ? deployment.pullRequestID : nil
        isRestart = deployment.restartOnly == true
        startedAt = deployment.createdAtDate
        finishedAt = deployment.finishedAtDate
    }
}

extension DeploymentItem {
    /// A deployment with plain values, for previews and the widget gallery.
    init(
        sample applicationName: String, status: String, message: String?, pullRequest: Int? = nil, minutesAgo: Double
    ) {
        id = UUID().uuidString
        pinID = ResourcePin(instanceID: UUID(), route: .application("a")).id
        self.applicationName = applicationName
        instanceName = "homelab"
        self.status = status
        self.message = message
        self.pullRequest = pullRequest
        startedAt = .now.addingTimeInterval(-minutesAgo * 60 - 90)
        finishedAt = DeploymentStatus.isUnderway(status) ? nil : .now.addingTimeInterval(-minutesAgo * 60)
    }

    static let samples: [DeploymentItem] = [
        DeploymentItem(sample: "web", status: "in_progress", message: "Tighten the pricing grid", minutesAgo: 1),
        DeploymentItem(
            sample: "web", status: "finished", message: "Try a darker hero", pullRequest: 42, minutesAgo: 14),
        DeploymentItem(sample: "api", status: "failed", message: "Bump the ORM to 7.2", minutesAgo: 38),
        DeploymentItem(sample: "api", status: "finished", message: "Cache team lookups", minutesAgo: 95),
        DeploymentItem(sample: "worker", status: "finished", message: nil, minutesAgo: 180),
        DeploymentItem(
            sample: "web", status: "failed", message: "Swap the font loader", pullRequest: 41, minutesAgo: 260),
        DeploymentItem(sample: "docs", status: "cancelled-by-user", message: "Draft the API guide", minutesAgo: 400),
    ]
}

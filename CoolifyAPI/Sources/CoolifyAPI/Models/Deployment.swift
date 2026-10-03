import Foundation

/// One deployment record. `pull_request_id` of `0` is a normal deploy; any greater value is a preview.
public struct Deployment: Decodable, Sendable, Identifiable, Hashable {
    public var logs: String?
    public var deploymentUUID: String
    public var applicationID: Int?
    public var pullRequestID: Int
    public var status: String?
    public var applicationName: String?
    public var restartOnly: Bool?
    /// Set when the deployment ran an image Coolify kept, through `rollback(_:to:)` or Coolify's own Rollback page.
    public var rollback: Bool?
    public var commit: String?
    public var commitMessage: String?
    public var isAPI: Bool?
    public var deploymentURL: String?
    public var createdAt: String?
    public var updatedAt: String?
    /// Newer Coolify builds stamp this when the queue item ends. Older ones leave only `updatedAt`.
    public var finishedAt: String?

    public var id: String { deploymentUUID }
    public var isPreview: Bool { pullRequestID > 0 }
    public var createdAtDate: Date? { createdAt.flatMap(CoolifyTimestamp.parse) }
    public var finishedAtDate: Date? { (finishedAt ?? updatedAt).flatMap(CoolifyTimestamp.parse) }

    /// Snake_case conversion yields `deploymentUuid` and `pullRequestId`, not the Swift acronym spellings.
    enum CodingKeys: String, CodingKey {
        case deploymentUUID = "deploymentUuid"
        case applicationID = "applicationId"
        case pullRequestID = "pullRequestId"
        case status
        case logs
        case applicationName
        case restartOnly
        case rollback
        case commit
        case commitMessage
        case isAPI = "isApi"
        case deploymentURL = "deploymentUrl"
        case createdAt
        case updatedAt
        case finishedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deploymentUUID = container.flexString(.deploymentUUID) ?? ""
        applicationID = container.flexInt(.applicationID)
        // Coolify has sent this as both an int and a numeric string.
        pullRequestID = container.flexInt(.pullRequestID) ?? 0
        logs = try container.decodeIfPresent(DeploymentOutput.self, forKey: .logs)?.text
        status = container.flexString(.status)
        applicationName = container.flexString(.applicationName)
        restartOnly = container.flexBool(.restartOnly)
        rollback = container.flexBool(.rollback)
        commit = container.flexString(.commit)
        commitMessage = container.flexString(.commitMessage)
        isAPI = container.flexBool(.isAPI)
        deploymentURL = container.flexString(.deploymentURL)
        createdAt = container.flexString(.createdAt)
        updatedAt = container.flexString(.updatedAt)
        finishedAt = container.flexString(.finishedAt)
    }
}

/// A page from `GET /deployments/applications/{uuid}`.
public struct DeploymentPage: Decodable, Sendable {
    public var count: Int
    public var deployments: [Deployment]
}

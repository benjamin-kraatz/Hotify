import Foundation

/// One deployment record. `pull_request_id` of `0` is a normal deploy; any greater value is a preview.
public struct Deployment: Decodable, Sendable, Identifiable, Hashable {
    public var deploymentUUID: String
    public var applicationID: Int?
    public var pullRequestID: Int
    public var status: String?
    public var applicationName: String?
    public var restartOnly: Bool?
    public var commit: String?
    public var isAPI: Bool?
    public var deploymentURL: String?

    public var id: String { deploymentUUID }
    public var isPreview: Bool { pullRequestID > 0 }

    /// Snake_case conversion yields `deploymentUuid` and `pullRequestId`, not the Swift acronym spellings.
    enum CodingKeys: String, CodingKey {
        case deploymentUUID = "deploymentUuid"
        case applicationID = "applicationId"
        case pullRequestID = "pullRequestId"
        case status
        case applicationName
        case restartOnly
        case commit
        case isAPI = "isApi"
        case deploymentURL = "deploymentUrl"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deploymentUUID = container.flexString(.deploymentUUID) ?? ""
        applicationID = container.flexInt(.applicationID)
        // Coolify has sent this as both an int and a numeric string.
        pullRequestID = container.flexInt(.pullRequestID) ?? 0
        status = container.flexString(.status)
        applicationName = container.flexString(.applicationName)
        restartOnly = container.flexBool(.restartOnly)
        commit = container.flexString(.commit)
        isAPI = container.flexBool(.isAPI)
        deploymentURL = container.flexString(.deploymentURL)
    }
}

/// A page from `GET /deployments/applications/{uuid}`.
public struct DeploymentPage: Decodable, Sendable {
    public var count: Int
    public var deployments: [Deployment]
}

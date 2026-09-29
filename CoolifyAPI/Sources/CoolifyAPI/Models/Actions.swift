import Foundation

/// The acknowledgement Coolify returns for start, stop, restart, cancel, preview delete, and variable delete.
public struct QueuedAction: Decodable, Sendable, Hashable {
    public var message: String?
    public var deploymentUUID: String?

    enum CodingKeys: String, CodingKey {
        case message
        case deploymentUUID = "deploymentUuid"
    }
}

/// One item inside a deploy response.
public struct QueuedDeployment: Decodable, Sendable, Hashable {
    public var message: String?
    public var resourceUUID: String?
    public var deploymentUUID: String?

    enum CodingKeys: String, CodingKey {
        case message
        case resourceUUID = "resourceUuid"
        case deploymentUUID = "deploymentUuid"
    }
}

/// Result of `POST /deploy`.
///
/// A single resource returns `deployments`. A deploy-by-tag returns the same rows under `details`.
public struct DeployResult: Decodable, Sendable {
    public var message: String?
    public var deployments: [QueuedDeployment]

    enum CodingKeys: String, CodingKey {
        case message
        case deployments
        case details
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = container.flexString(.message)
        if let rows = try? container.decode([QueuedDeployment].self, forKey: .deployments) {
            deployments = rows
        } else if let rows = try? container.decode([QueuedDeployment].self, forKey: .details) {
            deployments = rows
        } else {
            deployments = []
        }
    }
}

/// How much of a container log Coolify should return.
public enum LogWindow: Sendable {
    case lines(Int)
    case all

    var queryValue: String {
        switch self {
        case .lines(let count):
            String(count)
        case .all:
            "all"
        }
    }
}

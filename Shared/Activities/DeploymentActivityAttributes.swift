#if os(iOS)
import ActivityKit
import Foundation

/// A deploy started on this iPhone, shown as a Live Activity on the Lock Screen and in the Dynamic Island. The app
/// keeps it current while it may run. Hotify Relay can later update it by push.
/// Not on the main actor: ActivityKit reads it from its own threads.
nonisolated struct DeploymentActivityAttributes: ActivityAttributes {
    /// What changes while the deploy runs. A push from Hotify Relay passes through Apple unencrypted, so this holds
    /// the stage and a time, and nothing that names a resource. The keys are the ones the push gateway accepts.
    struct ContentState: Codable, Hashable {
        var stage: DeploymentStage
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case stage
            case updatedAt = "updated_at"
        }
    }

    var instanceID: UUID
    var applicationUUID: String
    var deploymentUUID: String
    var resourceName: String
    /// The project and environment, when known.
    var placeName: String?
    var startedAt: Date

    /// Opens the deployment in Hotify.
    @MainActor var link: URL {
        ResourceLink(
            instanceID: instanceID, route: .application(applicationUUID),
            place: .deployment(deploymentUUID, explains: false)
        ).url
    }
}
#endif

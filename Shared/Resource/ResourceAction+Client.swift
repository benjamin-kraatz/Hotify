import CoolifyAPI

extension CoolifyClient {
    /// Asks Coolify to run an action on a resource. Stopping leaves volumes in place.
    ///
    /// `deploymentID` is the deployment to cancel. Without it, cancelling does nothing.
    func run(_ action: ResourceAction, on route: ResourceRoute, deploymentID: String?) async throws {
        switch (route, action) {
        case (.application(let uuid), .start):
            _ = try await startApplication(uuid)
        case (.application(let uuid), .deploy):
            _ = try await deploy(uuid: uuid)
        case (.application(let uuid), .restart):
            _ = try await restartApplication(uuid)
        case (.application(let uuid), .stop):
            _ = try await stopApplication(uuid, dockerCleanup: false)
        case (.application, .cancelDeployment):
            guard let deploymentID, !deploymentID.isEmpty else { return }
            _ = try await cancelDeployment(deploymentID)
        case (.database(let uuid), .start):
            _ = try await startDatabase(uuid)
        case (.database(let uuid), .restart):
            _ = try await restartDatabase(uuid)
        case (.database(let uuid), .stop):
            _ = try await stopDatabase(uuid, dockerCleanup: false)
        case (.service(let uuid), .start):
            _ = try await startService(uuid)
        case (.service(let uuid), .restart):
            _ = try await restartService(uuid)
        case (.service(let uuid), .stop):
            _ = try await stopService(uuid, dockerCleanup: false)
        case (.database, .deploy), (.database, .cancelDeployment), (.service, .deploy), (.service, .cancelDeployment):
            // Only applications deploy. The action lists never offer these.
            return
        }
    }
}

import CoolifyAPI
import Foundation

/// Every application, database, and service on one instance, with production deployments in flight folded in.
struct InstanceScan {
    var instance: CoolifyInstance
    var resources: [ResourceSummary]

    /// Four requests: the three resource lists and the deployment queue.
    static func read(_ instanceID: UUID) async -> Result<InstanceScan, InstanceAccess.AccessError> {
        let instance: CoolifyInstance
        let client: CoolifyClient
        switch InstanceAccess.client(for: instanceID) {
        case .failure(let error):
            return .failure(error)
        case .success(let access):
            (instance, client) = access
        }
        do {
            async let applications = client.applications()
            async let databases = client.databases()
            async let services = client.services()
            // The queue only adds a "Deploying" state. Without it the resources still read.
            async let deployments = try? client.runningDeployments()
            let found = try await (applications, databases, services)
            let queue = (await deployments ?? []).filter { !$0.isPreview }
            let resources =
                found.0.map { application in
                    ResourceSummary(
                        application: application,
                        activeDeployment: queue.first { application.id != nil && $0.applicationID == application.id })
                } + found.1.map { ResourceSummary(database: $0) } + found.2.map { ResourceSummary(service: $0) }
            return .success(InstanceScan(instance: instance, resources: resources))
        } catch {
            return .failure(.problem(.unreachable))
        }
    }
}

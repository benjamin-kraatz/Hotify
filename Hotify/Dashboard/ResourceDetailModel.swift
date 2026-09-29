import CoolifyAPI
import Foundation

/// The application, database, or service open on the detail screen.
enum ResourceRoute: Hashable {
    case application(String)
    case database(String)
    case service(String)

    var busyTarget: BusyTarget {
        switch self {
        case .application(let uuid): .application(uuid)
        case .database(let uuid): .database(uuid)
        case .service(let uuid): .service(uuid)
        }
    }

    var showsDeployments: Bool {
        if case .application = self {
            return true
        }
        return false
    }
}

/// One deployment row. Built from `Deployment` so the view can take plain values in a preview.
struct DeploymentLine: Identifiable, Hashable {
    var id: String
    var status: String
    var detail: String
    var isPreview: Bool
    var url: URL?
}

extension DeploymentLine {
    init(deployment: Deployment, fallbackID: String) {
        let identifier = deployment.deploymentUUID
        id = identifier.isEmpty ? fallbackID : identifier
        status = deployment.status ?? "unknown"
        var parts: [String] = []
        if deployment.isPreview {
            parts.append("PR \(deployment.pullRequestID)")
        }
        if let commit = deployment.commit, !commit.isEmpty {
            parts.append(String(commit.prefix(7)))
        }
        if deployment.restartOnly == true {
            parts.append("restart")
        }
        detail = parts.joined(separator: " ")
        isPreview = deployment.isPreview
        if let raw = deployment.deploymentURL, !raw.isEmpty, let parsed = URL(string: raw) {
            url = parsed
        } else {
            url = nil
        }
    }
}

/// Loads logs for one resource, and deployment history when that resource is an application.
@Observable
final class ResourceDetailModel {
    var logs = ""
    var deployments: [DeploymentLine] = []
    var loadError: String?
    var actionError: String?
    var isLoading = false
    var isDeploying = false

    private var client: CoolifyClient?
    private var route: ResourceRoute?
    private var generation = 0
    private var refreshSerial = 0

    /// Clears the previous resource and points later refreshes at this one.
    func prepare(_ client: CoolifyClient, route: ResourceRoute) {
        generation += 1
        self.client = client
        self.route = route
        logs = ""
        deployments = []
        loadError = nil
        actionError = nil
        isDeploying = false
    }

    func refresh() async {
        guard let client, let route else { return }
        let generation = self.generation
        refreshSerial += 1
        let refreshSerial = self.refreshSerial
        if logs.isEmpty, deployments.isEmpty {
            isLoading = true
        }
        defer {
            if generation == self.generation, refreshSerial == self.refreshSerial {
                isLoading = false
            }
        }
        do {
            switch route {
            case .application(let uuid):
                async let logs = client.applicationLogs(uuid, showTimestamps: true)
                // One page. The history endpoint pages with skip and take and does not filter previews.
                async let page = client.applicationDeployments(uuid, take: 20)
                let loadedLogs = try await logs
                let loadedPage = try await page
                guard self.isCurrent(generation: generation, refreshSerial: refreshSerial) else { return }
                self.logs = loadedLogs
                deployments = loadedPage.deployments.enumerated().map { index, deployment in
                    DeploymentLine(deployment: deployment, fallbackID: "\(index)")
                }
            case .database(let uuid):
                let loadedLogs = try await client.databaseLogs(uuid, showTimestamps: true)
                guard self.isCurrent(generation: generation, refreshSerial: refreshSerial) else { return }
                logs = loadedLogs
                deployments = []
            case .service(let uuid):
                let loadedLogs = try await client.serviceLogs(uuid, showTimestamps: true)
                guard self.isCurrent(generation: generation, refreshSerial: refreshSerial) else { return }
                logs = loadedLogs
                deployments = []
            }
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(generation: generation, refreshSerial: refreshSerial) else { return }
            loadError = (error as? CoolifyError)?.message ?? error.localizedDescription
        }
    }

    private func isCurrent(generation: Int, refreshSerial: Int) -> Bool {
        generation == self.generation && refreshSerial == self.refreshSerial
    }

    /// Queues a deployment of the open application.
    func deploy() async {
        guard let client, case .application(let uuid) = route else { return }
        let generation = self.generation
        isDeploying = true
        defer {
            if generation == self.generation {
                isDeploying = false
            }
        }
        do {
            _ = try await client.deploy(uuid: uuid)
            guard generation == self.generation else { return }
            actionError = nil
            await refresh()
        } catch is CancellationError {
            return
        } catch {
            guard generation == self.generation else { return }
            actionError = (error as? CoolifyError)?.message ?? error.localizedDescription
        }
    }
}

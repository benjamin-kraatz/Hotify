import CoolifyAPI
import Foundation

/// One deployment row. Built from `Deployment` so the view can take plain values in a preview.
struct DeploymentLine: Identifiable, Hashable {
    var id: String
    var status: String
    var commit: String?
    var message: String?
    /// The pull request a preview deployment builds. `nil` for a production deployment.
    var pullRequest: Int?
    var isRestart = false
    var startedAt: Date?
    var finishedAt: Date?
    var url: URL?

    var isPreview: Bool { pullRequest != nil }

    var heat: Heat {
        switch status {
        case "finished": .lit
        case "in_progress": .warming
        case "failed": .troubled
        case "queued": .unknown
        default: .cold
        }
    }

    var statusLabel: String {
        switch status {
        case "finished": "Deployed"
        case "in_progress": "Deploying"
        case "failed": "Failed"
        case "queued": "Queued"
        case "cancelled-by-user": "Cancelled"
        default: status.prefix(1).uppercased() + status.dropFirst()
        }
    }

    /// How long the deployment ran. Only known once it has ended.
    var duration: Duration? {
        guard heat == .lit || heat == .troubled, let startedAt, let finishedAt, finishedAt > startedAt else {
            return nil
        }
        return .seconds(finishedAt.timeIntervalSince(startedAt).rounded())
    }
}

extension DeploymentLine {
    init(deployment: Deployment, fallbackID: String) {
        let identifier = deployment.deploymentUUID
        id = identifier.isEmpty ? fallbackID : identifier
        status = deployment.status ?? "unknown"
        if let commit = deployment.commit, !commit.isEmpty, commit != "HEAD" {
            self.commit = String(commit.prefix(7))
        }
        if let message = deployment.commitMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            // Only the subject line. The body belongs in the git host, not a list row.
            self.message = message.components(separatedBy: .newlines).first
        }
        pullRequest = deployment.isPreview ? deployment.pullRequestID : nil
        isRestart = deployment.restartOnly == true
        startedAt = deployment.createdAtDate
        finishedAt = deployment.finishedAtDate
        if let raw = deployment.deploymentURL, !raw.isEmpty, let parsed = URL(string: raw) {
            url = parsed
        }
    }
}

/// Loads logs for one resource, and deployment history when that resource is an application.
@Observable
final class ResourceDetailModel {
    var logs = "" {
        didSet { logLines = LogLine.parse(logs) }
    }
    private(set) var logLines: [LogLine] = []
    var deployments: [DeploymentLine] = []
    var loadError: String?
    var actionError: String?
    var isLoading = false
    var isDeploying = false
    /// How many trailing log lines to ask Coolify for.
    var logLineCount = 100
    /// The service container whose logs to read, by its Coolify `name`. `nil` skips the request.
    private(set) var logSource: String?

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
                async let logs = client.applicationLogs(uuid, window: .lines(logLineCount), showTimestamps: true)
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
                let loadedLogs = try await client.databaseLogs(uuid, window: .lines(logLineCount), showTimestamps: true)
                guard self.isCurrent(generation: generation, refreshSerial: refreshSerial) else { return }
                logs = loadedLogs
                deployments = []
            case .service(let uuid):
                guard let logSource else {
                    logs = ""
                    loadError = nil
                    return
                }
                let loadedLogs = try await client.serviceLogs(
                    uuid,
                    subServiceName: logSource,
                    window: .lines(logLineCount),
                    showTimestamps: true
                )
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

    /// Points service logs at another container and reloads. Pass `nil` for a stopped one; Coolify refuses those.
    func setLogSource(_ name: String?) async {
        guard name != logSource else { return }
        logSource = name
        logs = ""
        await refresh()
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

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

/// Which log the detail screen reads.
enum LogSource: Hashable {
    /// The application's or database's own container.
    case resource
    /// One container of a service, by its Coolify `name`.
    case container(String)
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
    var isLoading = false
    /// How many trailing log lines to ask Coolify for.
    var logLineCount = 100
    /// `nil` skips the log request. Coolify refuses one for a stopped container.
    private(set) var logSource: LogSource?

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
    }

    /// Loads the log and the deployment history side by side. One failing leaves the other on screen,
    /// because a stopped app has no log but still has the history that explains why.
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

        async let loadedLogs = loadLogs(client, route: route, source: logSource)
        async let loadedDeployments = loadDeployments(client, route: route)
        let logResult = await loadedLogs
        let deploymentResult = await loadedDeployments
        guard isCurrent(generation: generation, refreshSerial: refreshSerial) else { return }

        var errors: [String] = []
        switch logResult {
        case .success(let text):
            logs = text ?? ""
        case .failure(let error):
            errors.append(Self.message(for: error))
        case nil:
            break
        }
        switch deploymentResult {
        case .success(let lines):
            deployments = lines
        case .failure(let error):
            errors.append(Self.message(for: error))
        case nil:
            break
        }
        loadError = errors.first
    }

    /// `.success(nil)` when there is no log to ask for. `nil` when the request was cancelled.
    private func loadLogs(_ client: CoolifyClient, route: ResourceRoute, source: LogSource?) async
        -> Result<String?, any Error>?
    {
        guard let source else { return .success(nil) }
        do {
            switch (route, source) {
            case (.application(let uuid), _):
                return .success(
                    try await client.applicationLogs(uuid, window: .lines(logLineCount), showTimestamps: true))
            case (.database(let uuid), _):
                return .success(try await client.databaseLogs(uuid, window: .lines(logLineCount), showTimestamps: true))
            case (.service(let uuid), .container(let name)):
                return .success(
                    try await client.serviceLogs(
                        uuid,
                        subServiceName: name,
                        window: .lines(logLineCount),
                        showTimestamps: true
                    )
                )
            case (.service, .resource):
                return .success(nil)
            }
        } catch is CancellationError {
            return nil
        } catch {
            return .failure(error)
        }
    }

    /// `nil` for a database or service, which have no deployments, or when the request was cancelled.
    private func loadDeployments(_ client: CoolifyClient, route: ResourceRoute) async
        -> Result<[DeploymentLine], any Error>?
    {
        guard case .application(let uuid) = route else { return nil }
        do {
            // One page. The history endpoint pages with skip and take and does not filter previews.
            let page = try await client.applicationDeployments(uuid, take: 20)
            return .success(
                page.deployments.enumerated().map { index, deployment in
                    DeploymentLine(deployment: deployment, fallbackID: "\(index)")
                }
            )
        } catch is CancellationError {
            return nil
        } catch {
            return .failure(error)
        }
    }

    private static func message(for error: Error) -> String {
        (error as? CoolifyError)?.message ?? error.localizedDescription
    }

    /// Points the log at another source and reloads. Pass `nil` for a stopped one.
    func setLogSource(_ source: LogSource?) async {
        guard source != logSource else { return }
        logSource = source
        logs = ""
        await refresh()
    }

    private func isCurrent(generation: Int, refreshSerial: Int) -> Bool {
        generation == self.generation && refreshSerial == self.refreshSerial
    }
}

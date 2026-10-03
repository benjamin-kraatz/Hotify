import CoolifyAPI
import Foundation

/// What Hotify last saw on one instance, and the notices a new look turns up. The first look only sets what "before"
/// means, so launching Hotify never notifies about the state things were already in.
struct InstanceWatch {
    private var resources: [ResourceRoute: ResourceSummary] = [:]
    private var running: [String: RunningDeployment] = [:]
    private var servers: [String: (name: String, isReachable: Bool)] = [:]
    private var backups: [String: SeenBackup] = [:]
    private var places: [Int: ResourcePlace] = [:]
    private var placesLoadedAt: Date?
    private var backupsCheckedAt: Date?
    private var hasBaseline = false
    private var failures = 0
    private var lastAttempt: Date?

    /// Backups change at most every few minutes, and each database is its own request.
    private static let backupInterval: TimeInterval = 300
    private static let placesMaxAge: TimeInterval = 300
    /// A stop or restart started here doesn't come back as a notification for this long.
    private static let quietAfterLocalAction: TimeInterval = 300

    /// A deployment seen queued or building, until it ends.
    private struct RunningDeployment {
        var route: ResourceRoute?
        var name: String
        var pullRequest: Int
        var place: ResourcePlace?
        var firstSeen: Date
    }

    private struct SeenBackup {
        var executions: Set<String>
        var isOverdue: Bool
    }

    /// After 3 failed looks in a row, one every 2 minutes is enough.
    var isDue: Bool {
        guard failures >= 3, let lastAttempt else { return true }
        return Date.now.timeIntervalSince(lastAttempt) >= 120
    }

    mutating func check(client: CoolifyClient, instanceID: UUID) async -> [Notice] {
        lastAttempt = .now
        let loaded: (apps: [Application], databases: [Database], services: [Service], deployments: [Deployment])
        let loadedServers: [Server]
        do {
            async let apps = client.applications()
            async let databases = client.databases()
            async let services = client.services()
            async let deployments = client.runningDeployments()
            async let servers = client.servers()
            loaded = try await (apps, databases, services, deployments)
            loadedServers = try await servers
            failures = 0
        } catch {
            failures += 1
            return []
        }
        await loadPlacesIfNeeded(client)

        var notices: [Notice] = []
        let current = summaries(loaded.apps, loaded.databases, loaded.services, loaded.deployments)
        if hasBaseline {
            notices += downNotices(current, instanceID: instanceID)
            notices += serverNotices(loadedServers, instanceID: instanceID)
        }
        notices += await deploymentNotices(
            loaded.deployments, apps: loaded.apps, client: client, instanceID: instanceID)
        notices += await backupNotices(loaded.databases, current: current, client: client, instanceID: instanceID)

        resources = current
        servers = Dictionary(
            loadedServers.map { ($0.uuid, ($0.name, $0.isReachable ?? $0.settings?.isReachable ?? true)) }
        ) { first, _ in first }
        hasBaseline = true
        return notices
    }

    // MARK: Resources

    private func summaries(
        _ apps: [Application], _ databases: [Database], _ services: [Service], _ deployments: [Deployment]
    ) -> [ResourceRoute: ResourceSummary] {
        let list =
            apps.map { app in
                ResourceSummary(
                    application: app,
                    place: app.environmentID.flatMap { places[$0] },
                    activeDeployment: deployments.first { !$0.isPreview && $0.applicationID == app.id && app.id != nil }
                )
            }
            + databases.map { ResourceSummary(database: $0, place: $0.environmentID.flatMap { places[$0] }) }
            + services.map { ResourceSummary(service: $0, place: $0.environmentID.flatMap { places[$0] }) }
        return Dictionary(list.map { ($0.route, $0) }) { first, _ in first }
    }

    /// Something that ran, and now stopped or turned unhealthy. A deploy restarts containers and a stop from here is
    /// expected, so neither counts.
    private func downNotices(_ current: [ResourceRoute: ResourceSummary], instanceID: UUID) -> [Notice] {
        current.compactMap { route, now in
            guard let before = resources[route], before.heat == .lit, now.heat == .cold || now.heat == .troubled,
                !now.isDeploying, !before.isDeploying,
                !LocalActions.touched(route, within: Self.quietAfterLocalAction)
            else { return nil }
            return Notice(
                instanceID: instanceID,
                event: .resourceDown,
                title: now.name,
                subtitle: Self.placeLine(now.place),
                body: now.heat == .cold ? "Stopped running." : "Turned unhealthy.",
                link: ResourceLink(instanceID: instanceID, route: route).url
            )
        }
    }

    // MARK: Servers

    private func serverNotices(_ loaded: [Server], instanceID: UUID) -> [Notice] {
        loaded.compactMap { server in
            guard let before = servers[server.uuid] else { return nil }
            let isReachable = server.isReachable ?? server.settings?.isReachable ?? true
            guard isReachable != before.isReachable else { return nil }
            return Notice(
                instanceID: instanceID,
                event: .serverReachability,
                title: server.name,
                body: isReachable ? "Coolify reaches it again." : "Coolify can't reach this server.",
                link: InstanceLink(instanceID: instanceID).url
            )
        }
    }

    // MARK: Deployments

    /// Notes deployments that started, and reads how each one that left the queue ended. Coolify's list only holds
    /// queued and building ones, so a deploy that starts and ends between two looks goes unseen.
    private mutating func deploymentNotices(
        _ deployments: [Deployment], apps: [Application], client: CoolifyClient, instanceID: UUID
    ) async -> [Notice] {
        let now = Date.now
        for deployment in deployments where !deployment.deploymentUUID.isEmpty {
            guard running[deployment.deploymentUUID] == nil else { continue }
            let app = apps.first { $0.id != nil && $0.id == deployment.applicationID }
            running[deployment.deploymentUUID] = RunningDeployment(
                route: app.map { .application($0.uuid) },
                name: app?.name ?? deployment.applicationName ?? "An application",
                pullRequest: deployment.pullRequestID,
                place: app?.environmentID.flatMap { places[$0] },
                firstSeen: now
            )
        }
        let stillRunning = Set(deployments.map(\.deploymentUUID))
        var notices: [Notice] = []
        for (id, seen) in running where !stillRunning.contains(id) {
            running[id] = nil
            guard let ended = try? await client.deployment(id) else { continue }
            if let notice = Self.notice(for: ended, seen: seen, id: id, instanceID: instanceID) {
                notices.append(notice)
            }
        }
        return notices
    }

    private static func notice(for deployment: Deployment, seen: RunningDeployment, id: String, instanceID: UUID)
        -> Notice?
    {
        let subject = deployment.commitMessage?.components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespaces)
        let detail = subject.flatMap { $0.isEmpty ? nil : "\n\($0)" } ?? ""
        let link = { (place: ResourceLink.Place) in
            seen.route.map { ResourceLink(instanceID: instanceID, route: $0, place: place).url }
        }
        switch deployment.status {
        case "failed":
            return Notice(
                instanceID: instanceID,
                event: .deploymentFailed,
                title: seen.name,
                subtitle: placeLine(seen.place),
                body: (seen.pullRequest > 0 ? "Preview #\(seen.pullRequest) failed." : "Deployment failed.") + detail,
                link: link(.deployment(id, explains: false)),
                explainLink: link(.deployment(id, explains: true)),
                // A preview's failure leaves production as it was, so there is nothing to roll back.
                rollbackLink: seen.pullRequest > 0 ? nil : link(.rollback)
            )
        case "finished":
            // A deploy noted here a little before Coolify listed it counts as this device's.
            let isLocal = seen.route.map { LocalActions.deployed($0, since: seen.firstSeen.addingTimeInterval(-180)) }
            return Notice(
                instanceID: instanceID,
                event: isLocal == true ? .deploymentFinished : .deploymentFinishedElsewhere,
                title: seen.name,
                subtitle: placeLine(seen.place),
                body: (seen.pullRequest > 0 ? "Preview #\(seen.pullRequest) is ready." : "Deployed.") + detail,
                link: link(.deployment(id, explains: false))
            )
        default:
            // Cancelled, or a status Hotify doesn't know. Neither is news.
            return nil
        }
    }

    // MARK: Backups

    /// A new failed run, or a schedule that just became late. Checked every 5 minutes.
    private mutating func backupNotices(
        _ databases: [Database], current: [ResourceRoute: ResourceSummary], client: CoolifyClient, instanceID: UUID
    ) async -> [Notice] {
        if let checked = backupsCheckedAt, Date.now.timeIntervalSince(checked) < Self.backupInterval { return [] }
        backupsCheckedAt = .now
        var notices: [Notice] = []
        for database in databases {
            guard let schedules = try? await client.databaseBackups(database.uuid) else { continue }
            let summary = current[.database(database.uuid)]
            let name = summary?.name ?? database.name ?? "A database"
            let link = ResourceLink(instanceID: instanceID, route: .database(database.uuid), place: .backups).url
            for schedule in schedules {
                let key = "\(database.uuid)/\(schedule.uuid)"
                let seen = SeenBackup(
                    executions: Set(schedule.executions.map(\.uuid)), isOverdue: schedule.isOverdue(at: .now))
                defer { backups[key] = seen }
                guard let before = backups[key] else { continue }
                for run in schedule.history where !before.executions.contains(run.uuid) && run.heat == .troubled {
                    notices.append(
                        Notice(
                            instanceID: instanceID, event: .backupFailed, title: name,
                            subtitle: Self.placeLine(summary?.place),
                            body: "Backup failed." + (run.message.map { "\n\($0)" } ?? ""), link: link))
                }
                if seen.isOverdue, !before.isOverdue {
                    notices.append(
                        Notice(
                            instanceID: instanceID, event: .backupFailed, title: name,
                            subtitle: Self.placeLine(summary?.place),
                            body: "No good backup since the schedule's last run was due.", link: link))
                }
            }
        }
        return notices
    }

    // MARK: Places

    private mutating func loadPlacesIfNeeded(_ client: CoolifyClient) async {
        if let loadedAt = placesLoadedAt, Date.now.timeIntervalSince(loadedAt) < Self.placesMaxAge { return }
        guard let projects = try? await client.projects() else { return }
        var detailed: [Project] = []
        for project in projects {
            if let detail = try? await client.project(project.uuid) { detailed.append(detail) }
        }
        places = ResourcePlace.index(detailed)
        placesLoadedAt = .now
    }

    private static func placeLine(_ place: ResourcePlace?) -> String? {
        guard let place else { return nil }
        return place.environmentName.isEmpty ? place.projectName : "\(place.projectName) · \(place.environmentName)"
    }
}

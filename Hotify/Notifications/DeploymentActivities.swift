#if os(iOS)
import ActivityKit
import BackgroundTasks
import CoolifyAPI
import Foundation
import UIKit
import UserNotifications

/// Starts a Live Activity for each deploy started on this iPhone, keeps it current while Hotify may run, and ends it
/// with the result, with a notification then.
///
/// Without push, iOS can't wake Hotify when a deploy ends. The app updates the activity while it's open, for the
/// short time iOS grants after you leave it, and when a background refresh runs, which iOS schedules as it likes.
/// In between, the activity turns stale and says to open Hotify.
@Observable
final class DeploymentActivities {
    static let refreshTaskID = "com.sebastiankraatz.Hotify.deployments"
    /// An activity that hasn't heard from Hotify for this long says so.
    private static let staleAfter: TimeInterval = 300
    /// A deploy counts as this iPhone's when it noted one for the app this recently.
    private static let localWindow: TimeInterval = 300

    private var store: InstanceStore?
    private var followTask: Task<Void, Never>?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    func connect(_ store: InstanceStore) {
        self.store = store
    }

    private var running: [Activity<DeploymentActivityAttributes>] {
        Activity<DeploymentActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    /// After a dashboard poll: starts activities for deploys started here, and brings this instance's up to date.
    func observe(_ snapshot: DashboardSnapshot, instance: CoolifyInstance, client: CoolifyClient) async {
        let now = Date.now
        for resource in snapshot.resources where resource.kind == .application && resource.isDeploying {
            guard case .application(let uuid) = resource.route, let deployment = resource.activeDeploymentID,
                LocalActions.deployed(resource.route, since: now.addingTimeInterval(-Self.localWindow)),
                !running.contains(where: { $0.attributes.deploymentUUID == deployment })
            else { continue }
            start(
                DeploymentActivityAttributes(
                    instanceID: instance.id, applicationUUID: uuid, deploymentUUID: deployment,
                    resourceName: resource.name, placeName: Self.placeName(resource.place), startedAt: now))
        }
        for activity in running where activity.attributes.instanceID == instance.id {
            await refresh(activity, client: client)
        }
    }

    /// Brings every running activity up to date, whichever instance it belongs to. For the background.
    func refreshAll() async {
        guard let store else { return }
        for activity in running {
            guard let instance = store.instances.first(where: { $0.id == activity.attributes.instanceID }),
                let client = store.client(for: instance)
            else { continue }
            await refresh(activity, client: client)
        }
    }

    /// Keeps the activities current for the short time iOS grants after Hotify leaves the screen, then asks for a
    /// background refresh to try again later.
    func followInBackground() {
        guard !running.isEmpty, followTask == nil else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Follow deploys") { [weak self] in
            // iOS calls this on the main thread when the time it granted runs out.
            MainActor.assumeIsolated { self?.stopFollowing() }
        }
        followTask = Task { [weak self] in
            while let self, !Task.isCancelled, !self.running.isEmpty {
                await self.refreshAll()
                try? await Task.sleep(for: .seconds(5))
            }
            self?.stopFollowing()
        }
    }

    private func stopFollowing() {
        followTask?.cancel()
        followTask = nil
        scheduleRefresh()
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    /// Asks iOS for a background refresh while a deploy still runs. iOS decides when, if ever.
    func scheduleRefresh() {
        guard !running.isEmpty else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = .now.addingTimeInterval(60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: Activities

    private func start(_ attributes: DeploymentActivityAttributes) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = DeploymentActivityAttributes.ContentState(stage: .building, updatedAt: .now)
        _ = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: .now.addingTimeInterval(Self.staleAfter)),
            pushType: nil)
        Task { await Self.requestNotificationsIfNeeded() }
    }

    private func refresh(_ activity: Activity<DeploymentActivityAttributes>, client: CoolifyClient) async {
        guard let deployment = try? await client.deployment(activity.attributes.deploymentUUID) else { return }
        let stage = DeploymentStage(status: deployment.status)
        let state = DeploymentActivityAttributes.ContentState(stage: stage, updatedAt: .now)
        if stage.isOver {
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .default)
            await Self.notify(stage, attributes: activity.attributes)
        } else {
            await activity.update(
                ActivityContent(state: state, staleDate: .now.addingTimeInterval(Self.staleAfter)))
        }
    }

    // MARK: Notifications

    /// Asked with the first activity, which follows a deploy the user just started. Not at launch.
    private static func requestNotificationsIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    private static func notify(_ stage: DeploymentStage, attributes: DeploymentActivityAttributes) async {
        guard stage != .cancelled else { return }
        let content = UNMutableNotificationContent()
        content.title = attributes.resourceName
        if let place = attributes.placeName { content.subtitle = place }
        content.body = stage == .failed ? "Deployment failed." : "Deployed."
        content.sound = .default
        content.threadIdentifier = attributes.instanceID.uuidString
        content.interruptionLevel = stage == .failed ? .timeSensitive : .active
        content.userInfo = ["url": attributes.link.absoluteString]
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: attributes.deploymentUUID, content: content, trigger: nil))
    }

    private static func placeName(_ place: ResourcePlace?) -> String? {
        guard let place else { return nil }
        return place.environmentName.isEmpty ? place.projectName : "\(place.projectName) · \(place.environmentName)"
    }
}
#endif

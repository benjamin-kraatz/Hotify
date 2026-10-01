import AppIntents
import Foundation
import WidgetKit

/// One moment of a Recent Deployments widget.
struct DeploymentsEntry: TimelineEntry {
    var date: Date
    var items: [DeploymentItem]
    var problems: [String] = []
    var followed: Int
    /// Applications there were to follow, when the widget picked them itself.
    var available: Int?
    var hasNoInstances = false
    var checkedAt: Date?
}

/// Reads the followed applications' histories. Looks again within a minute while a build runs.
struct DeploymentsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DeploymentsEntry {
        DeploymentsEntry(date: .now, items: DeploymentItem.samples, followed: 4, checkedAt: .now)
    }

    func snapshot(for configuration: RecentDeploymentsIntent, in context: Context) async -> DeploymentsEntry {
        if context.isPreview { return placeholder(in: context) }
        return await entry(for: configuration)
    }

    func timeline(for configuration: RecentDeploymentsIntent, in context: Context) async -> Timeline<
        DeploymentsEntry
    > {
        let entry = await entry(for: configuration)
        let isBusy = entry.items.contains(where: \.isUnderway)
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(isBusy ? 60 : 15 * 60)))
    }

    private func entry(for configuration: RecentDeploymentsIntent) async -> DeploymentsEntry {
        guard !AppGroup.instances().isEmpty else {
            return DeploymentsEntry(date: .now, items: [], followed: 0, hasNoInstances: true)
        }
        let feed = await DeploymentFeed.read(picked: configuration.applications ?? [])
        return DeploymentsEntry(
            date: .now, items: feed.items, problems: feed.problems, followed: feed.followed,
            available: feed.available, checkedAt: .now)
    }
}

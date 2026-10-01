import AppIntents
import SwiftUI
import WidgetKit

/// Which applications a Recent Deployments widget follows.
struct RecentDeploymentsIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Recent Deployments"
    static let description = IntentDescription("The newest deployments of your applications, previews included.")

    @Parameter(
        title: "Applications",
        description: "Leave empty to follow the first applications on each instance.",
        size: 12,
        query: ResourceQuery(kind: .application)
    )
    var applications: [ResourceEntity]?
}

/// The newest deployments, production in red and pull request previews in blue, each a tap from its history.
struct RecentDeploymentsWidget: Widget {
    static let kind = "com.sebastiankraatz.Hotify.deployments"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind, intent: RecentDeploymentsIntent.self, provider: DeploymentsProvider()
        ) { entry in
            RecentDeploymentsView(entry: entry)
        }
        .configurationDisplayName("Recent Deployments")
        .description("The newest deployments and previews of your applications. Tap one to open its history.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular]
        #else
        [.systemSmall, .systemMedium, .systemLarge]
        #endif
    }
}

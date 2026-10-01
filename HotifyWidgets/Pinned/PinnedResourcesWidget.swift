import SwiftUI
import WidgetKit

/// Up to six resources in sight, each with the action most likely wanted next.
struct PinnedResourcesWidget: Widget {
    static let kind = "com.sebastiankraatz.Hotify.pinned"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: PinnedResourcesIntent.self, provider: PinnedProvider()) {
            entry in
            PinnedResourcesView(entry: entry)
        }
        .configurationDisplayName("Pinned Resources")
        .description("Keep applications, databases, and services in sight. Start or stop them right here.")
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

import AppIntents
import WidgetKit

/// Which resources a Pinned Resources widget shows.
struct PinnedResourcesIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Pinned Resources"
    static let description = IntentDescription("Keep resources in sight, and start or stop them from the widget.")

    // A medium widget lists up to three in rows, or four in a grid.
    @Parameter(
        title: "Resources",
        size: [.systemSmall: 1, .systemMedium: 4, .systemLarge: 6, .accessoryRectangular: 1]
    )
    var resources: [ResourceEntity]?

    init() {}

    init(resources: [ResourceEntity]) {
        self.resources = resources
    }
}

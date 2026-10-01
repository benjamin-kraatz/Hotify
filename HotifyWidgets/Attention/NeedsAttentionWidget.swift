import AppIntents
import SwiftUI
import WidgetKit

/// Which instances a Needs Attention widget watches.
struct NeedsAttentionIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Needs Attention"
    static let description = IntentDescription("Whatever is unhealthy, starting, or deploying, on every instance.")

    @Parameter(title: "Instances", description: "Leave empty to watch every instance.")
    var instances: [InstanceEntity]?
}

/// Lists what wants a look across instances, with the fix at hand, and says so when nothing does.
struct NeedsAttentionWidget: Widget {
    static let kind = "com.sebastiankraatz.Hotify.attention"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: NeedsAttentionIntent.self, provider: AttentionProvider()) {
            entry in
            NeedsAttentionView(entry: entry)
        }
        .configurationDisplayName("Needs Attention")
        .description("What is unhealthy, starting, or deploying, with a restart at hand. Quiet when all is well.")
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

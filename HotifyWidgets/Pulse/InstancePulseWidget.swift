import AppIntents
import CoolifyAPI
import SwiftUI
import WidgetKit

/// Which instance an Instance widget counts.
struct InstancePulseIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Instance"
    static let description = IntentDescription("How much of an instance runs, and what wants a look.")

    @Parameter(title: "Instance")
    var instance: InstanceEntity?
}

/// One moment of an Instance widget.
struct PulseEntry: TimelineEntry {
    var date: Date
    /// Nil when no instance is saved in the app.
    var pulse: InstancePulse?
    var instanceID: UUID?
}

/// Counts the instance's resources about every quarter hour, as often as WidgetKit allows.
struct PulseProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PulseEntry {
        PulseEntry(date: .now, pulse: .sample)
    }

    func snapshot(for configuration: InstancePulseIntent, in context: Context) async -> PulseEntry {
        if context.isPreview { return placeholder(in: context) }
        return await entry(for: configuration)
    }

    func timeline(for configuration: InstancePulseIntent, in context: Context) async -> Timeline<PulseEntry> {
        let entry = await entry(for: configuration)
        // An unhealthy resource can stay that way all day, so a look sooner would only spend the daily budget.
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60)))
    }

    private func entry(for configuration: InstancePulseIntent) async -> PulseEntry {
        let id: UUID?
        if let instance = configuration.instance {
            id = instance.id
        } else {
            id = AppGroup.instances().first?.id
        }
        guard let id else { return PulseEntry(date: .now, pulse: nil) }
        let previous = WidgetLedger.load().pulses[id.uuidString]
        let pulse = await InstancePulse.read(id, previous: previous)
        WidgetLedger.update { $0.pulses[id.uuidString] = pulse }
        return PulseEntry(date: .now, pulse: pulse, instanceID: id)
    }
}

/// How much of an instance runs: a ring on the Lock Screen, a line above the clock, or a strip on the Home Screen.
struct InstancePulseWidget: Widget {
    static let kind = "com.sebastiankraatz.Hotify.instance"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: InstancePulseIntent.self, provider: PulseProvider()) { entry in
            InstancePulseView(entry: entry)
        }
        .configurationDisplayName("Instance")
        .description("How much of an instance runs, and what wants a look.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #else
        [.systemSmall]
        #endif
    }
}

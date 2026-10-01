import AppIntents
import SwiftUI
import WidgetKit

/// Which databases a Backups widget watches.
struct BackupsIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Backups"
    static let description = IntentDescription("Whether your databases' backups ran, and when.")

    @Parameter(
        title: "Databases",
        description: "Leave empty to watch the first databases on each instance.",
        size: 12,
        query: ResourceQuery(kind: .database)
    )
    var databases: [ResourceEntity]?
}

/// Whether each database's backups ran, failed, or fell behind their schedule, with Back Up Now at hand.
struct BackupsWidget: Widget {
    static let kind = "com.sebastiankraatz.Hotify.backups"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: BackupsIntent.self, provider: BackupsProvider()) { entry in
            BackupsView(entry: entry)
        }
        .configurationDisplayName("Backups")
        .description("Whether your databases' backups ran, failed, or fell behind. Back up again right here.")
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

/// One moment of a Backups widget.
struct BackupsEntry: TimelineEntry {
    var date: Date
    /// Failing first, then underway, then the oldest backup.
    var tiles: [BackupTile]
    var problems: [String] = []
    /// Databases there were to watch, when the widget picked them itself.
    var available: Int?
    var hasNoInstances = false
    var checkedAt: Date?
}

/// Reads backups about every half hour. A backup takes minutes, so one underway is checked again soon.
struct BackupsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BackupsEntry {
        BackupsEntry(date: .now, tiles: BackupTile.samples, checkedAt: .now)
    }

    func snapshot(for configuration: BackupsIntent, in context: Context) async -> BackupsEntry {
        if context.isPreview { return placeholder(in: context) }
        return await entry(for: configuration)
    }

    func timeline(for configuration: BackupsIntent, in context: Context) async -> Timeline<BackupsEntry> {
        let entry = await entry(for: configuration)
        let isBusy = entry.tiles.contains { $0.heat == .warming }
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(isBusy ? 120 : 30 * 60)))
    }

    private func entry(for configuration: BackupsIntent) async -> BackupsEntry {
        guard !AppGroup.instances().isEmpty else {
            return BackupsEntry(date: .now, tiles: [], hasNoInstances: true)
        }
        let result = await BackupProbe.read(picked: configuration.databases ?? [])
        let ledger = WidgetLedger.load()
        let now = Date.now
        let tiles = result.pins.map { pin in
            BackupTile(pin: pin, fallbackName: result.names[pin.id] ?? "Database", ledger: ledger, at: now)
        }
        return BackupsEntry(
            date: now, tiles: tiles.sorted(by: BackupTile.urgency), problems: result.problems,
            available: result.available, checkedAt: now)
    }
}

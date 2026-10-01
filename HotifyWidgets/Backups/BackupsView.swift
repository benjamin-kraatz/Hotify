import AppIntents
import SwiftUI
import WidgetKit

/// Draws a Backups widget for its size.
struct BackupsView: View {
    var entry: BackupsEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) {
                HeatBackdrop(heats: entry.tiles.first.map { [$0.heat] } ?? [])
            }
    }

    @ViewBuilder
    private var content: some View {
        if entry.hasNoInstances {
            BackupsMessage(title: "No instance yet", detail: "Add a Coolify instance in Hotify.")
        } else if entry.tiles.isEmpty {
            BackupsMessage(
                title: "No databases", detail: entry.problems.first ?? "This widget has no databases to watch.")
        } else {
            switch family {
            case .systemSmall:
                BackupHero(tile: entry.tiles[0], others: entry.tiles.count - 1)
            #if os(iOS)
            case .accessoryRectangular:
                BackupAccessory(tile: entry.tiles[0])
            #endif
            case .systemMedium:
                BackupList(entry: entry, capacity: 3, showsHeader: false)
            default:
                BackupList(entry: entry, capacity: 6, showsHeader: true)
            }
        }
    }
}

/// A flame and two lines, for a widget with nothing to list.
struct BackupsMessage: View {
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            FlameGlyph(heat: .cold, height: 28)
            Spacer(minLength: 4)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Runs a database's backup once.
struct BackUpButton: View {
    var tile: BackupTile
    var backupUUID: String
    var style: ButtonFace.Style = .icon

    var body: some View {
        Button(intent: BackUpNowIntent(pin: tile.pin, backupUUID: backupUUID)) {
            ButtonFace(title: "Back Up", systemImage: "arrow.down.doc.fill", style: style)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back up \(tile.name) now")
    }
}

/// The status and how long ago, amber when it wants a look.
struct BackupStatus: View {
    var tile: BackupTile

    var body: some View {
        HStack(spacing: 4) {
            Text(tile.status)
                .foregroundStyle(tile.isAlert ? AnyShapeStyle(.glow) : AnyShapeStyle(.secondary))
            if let date = tile.date, tile.heat != .warming {
                Text("·").foregroundStyle(.tertiary)
                Text(
                    .currentDate, format: .reference(to: date, allowedFields: [.minute, .hour, .day], maxFieldCount: 1)
                )
                .foregroundStyle(.tertiary)
            }
        }
        .lineLimit(1)
    }
}

/// The small widget: the database that most wants a look.
struct BackupHero: View {
    var tile: BackupTile
    /// How many more the widget watches.
    var others: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                FlameGlyph(heat: tile.heat, height: 36)
                    .widgetAccentable()
                Spacer(minLength: 4)
                if let backupUUID = tile.backupUUID, tile.heat != .lit {
                    BackUpButton(tile: tile, backupUUID: backupUUID)
                }
            }
            Spacer(minLength: 4)
            Text(tile.name)
                .font(.display(.headline))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            BackupStatus(tile: tile)
                .font(.caption)
                .padding(.top, 2)
            if others > 0 {
                Text(others == 1 ? "and 1 more database" : "and \(others) more databases")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(tile.link)
    }
}

/// One database as a row. The link and the button sit side by side.
struct BackupRow: View {
    var tile: BackupTile

    var body: some View {
        HStack(spacing: 6) {
            Link(destination: tile.link) {
                HStack(spacing: 12) {
                    FlameGlyph(heat: tile.heat, height: 22)
                        .widgetAccentable()
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(tile.name)
                                .font(.subheadline.weight(.semibold))
                            if let engine = tile.engine {
                                Text(engine)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .lineLimit(1)
                        BackupStatus(tile: tile)
                            .font(.caption)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
            }
            if let backupUUID = tile.backupUUID {
                BackUpButton(tile: tile, backupUUID: backupUUID, style: tile.heat == .lit ? .icon : .labeled)
            }
        }
    }
}

/// The medium and large widgets: one row per database, the ones that want a look first.
struct BackupList: View {
    var entry: BackupsEntry
    var capacity: Int
    var showsHeader: Bool

    private var shown: [BackupTile] { Array(entry.tiles.prefix(capacity)) }
    private var failing: Int { entry.tiles.filter { $0.heat == .troubled }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsHeader {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Backups")
                        .font(.display(.subheadline))
                    if failing > 0 {
                        Text(failing == 1 ? "1 needs a look" : "\(failing) need a look")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.glow)
                    }
                    Spacer(minLength: 4)
                    if let checkedAt = entry.checkedAt {
                        Text(
                            .currentDate,
                            format: .reference(to: checkedAt, allowedFields: [.minute, .hour, .day], maxFieldCount: 1)
                        )
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }
                }
                .lineLimit(1)
            }
            ForEach(shown) { tile in
                BackupRow(tile: tile)
                    .frame(maxHeight: 46)
            }
            if showsHeader, let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: String? {
        var parts: [String] = []
        let hidden = entry.tiles.count - shown.count
        if hidden > 0 { parts.append("and \(hidden) more") }
        if let available = entry.available, available > entry.tiles.count {
            parts.append("\(entry.tiles.count) of \(available) databases · edit to pick")
        }
        parts += entry.problems
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

#if os(iOS)
/// The Lock Screen rectangle: the database that most wants a look.
struct BackupAccessory: View {
    var tile: BackupTile

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                FlameGlyph(heat: tile.heat, height: 14)
                    .widgetAccentable()
                Text(tile.name)
                    .font(.headline)
                    .lineLimit(1)
            }
            BackupStatus(tile: tile)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(tile.link)
    }
}

#Preview("Lock Screen", as: .accessoryRectangular) {
    BackupsWidget()
} timeline: {
    BackupsEntry(date: .now, tiles: BackupTile.samples, checkedAt: .now)
}
#endif

#Preview("Small", as: .systemSmall) {
    BackupsWidget()
} timeline: {
    BackupsEntry(date: .now, tiles: BackupTile.samples, checkedAt: .now)
    BackupsEntry(date: .now, tiles: [BackupTile.samples[2]], checkedAt: .now)
}

#Preview("Medium", as: .systemMedium) {
    BackupsWidget()
} timeline: {
    BackupsEntry(date: .now, tiles: BackupTile.samples, checkedAt: .now)
}

#Preview("Large", as: .systemLarge) {
    BackupsWidget()
} timeline: {
    BackupsEntry(date: .now, tiles: BackupTile.samples, available: 14, checkedAt: .now)
}

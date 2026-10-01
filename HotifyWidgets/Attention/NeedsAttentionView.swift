import SwiftUI
import WidgetKit

/// Draws a Needs Attention widget for its size.
struct NeedsAttentionView: View {
    var entry: AttentionEntry

    @Environment(\.widgetFamily) private var family

    private var capacity: Int {
        switch family {
        case .systemSmall: 1
        case .systemMedium: 3
        default: 6
        }
    }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                HeatBackdrop(heats: entry.isQuiet ? (entry.hasNoInstances ? [] : [.lit]) : [.troubled])
            }
    }

    @ViewBuilder
    private var content: some View {
        if entry.hasNoInstances {
            AttentionMessage(
                heat: .cold, title: "No instance yet", detail: "Add a Coolify instance in Hotify.", checkedAt: nil)
        } else {
            switch family {
            case .systemSmall:
                AttentionSmall(entry: entry)
            #if os(iOS)
            case .accessoryRectangular:
                AttentionAccessory(entry: entry)
            #endif
            default:
                AttentionList(entry: entry, capacity: capacity)
            }
        }
    }
}

/// How many want a look, as a heading.
private func attentionTitle(_ count: Int) -> String {
    count == 1 ? "1 needs a look" : "\(count) need a look"
}

/// What a quiet widget says.
private func quietDetail(_ entry: AttentionEntry) -> String {
    entry.instanceCount == 1 ? "Nothing needs a look." : "Nothing on \(entry.instanceCount) instances needs a look."
}

/// A flame, a heading, and a line, for a widget with nothing to list.
struct AttentionMessage: View {
    var heat: Heat
    var title: String
    var detail: String
    var checkedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            FlameGlyph(heat: heat, height: 30)
                .widgetAccentable()
            Spacer(minLength: 4)
            Text(title)
                .font(.display(.headline))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let checkedAt {
                Text(
                    .currentDate,
                    format: .reference(to: checkedAt, allowedFields: [.minute, .hour, .day], maxFieldCount: 1)
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// The small widget: how many want a look, and the most urgent one with its fix.
struct AttentionSmall: View {
    var entry: AttentionEntry

    var body: some View {
        if let first = entry.tiles.first {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    FlameGlyph(heat: first.heat, height: 30)
                        .widgetAccentable()
                    Spacer(minLength: 4)
                    if let primary = first.primary {
                        ActionButton(tile: first, action: primary)
                    }
                }
                Spacer(minLength: 4)
                Text(attentionTitle(entry.tiles.count))
                    .font(.display(.subheadline))
                    .foregroundStyle(.glow)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(first.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.top, 4)
                TileStatus(tile: first)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(first.pin.link)
        } else if let problem = entry.problems.first {
            AttentionMessage(heat: .unknown, title: "Out of reach", detail: problem, checkedAt: entry.checkedAt)
        } else {
            AttentionMessage(heat: .lit, title: "All quiet", detail: quietDetail(entry), checkedAt: entry.checkedAt)
        }
    }
}

/// The medium and large widgets: a heading, then one row per resource, then what did not fit.
struct AttentionList: View {
    var entry: AttentionEntry
    var capacity: Int

    private var shown: [PinTile] { Array(entry.tiles.prefix(capacity)) }
    private var hidden: Int { entry.tiles.count - shown.count }

    var body: some View {
        if entry.tiles.isEmpty {
            HStack(alignment: .center, spacing: 16) {
                FlameGlyph(heat: entry.problems.isEmpty ? .lit : .unknown, height: 52)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.problems.isEmpty ? "All quiet" : "Out of reach")
                        .font(.display(.title3))
                    Text(entry.problems.isEmpty ? quietDetail(entry) : entry.problems.joined(separator: "\n"))
                        .font(.caption)
                        .foregroundStyle(entry.problems.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.glow))
                        .lineLimit(3)
                    if let checkedAt = entry.checkedAt {
                        Text(
                            .currentDate,
                            format: .reference(to: checkedAt, allowedFields: [.minute, .hour, .day], maxFieldCount: 1)
                        )
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(attentionTitle(entry.tiles.count))
                        .font(.display(.subheadline))
                        .foregroundStyle(.glow)
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
                ForEach(shown) { tile in
                    TileRow(tile: tile, showsInstance: entry.instanceCount > 1)
                        .frame(maxHeight: 44)
                }
                if hidden > 0 || !entry.problems.isEmpty {
                    Text(footer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var footer: String {
        var parts: [String] = []
        if hidden > 0 { parts.append("and \(hidden) more") }
        parts += entry.problems
        return parts.joined(separator: " · ")
    }
}

#if os(iOS)
/// The Lock Screen rectangle: how many want a look, and the first of them.
struct AttentionAccessory: View {
    var entry: AttentionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                FlameGlyph(heat: entry.tiles.first?.heat ?? (entry.problems.isEmpty ? .lit : .unknown), height: 14)
                    .widgetAccentable()
                Text(
                    entry.tiles.isEmpty
                        ? (entry.problems.isEmpty ? "All quiet" : "Out of reach") : attentionTitle(entry.tiles.count)
                )
                .font(.headline)
                .lineLimit(1)
            }
            if let first = entry.tiles.first {
                Text("\(first.name) · \(first.status)")
                    .font(.subheadline)
                    .lineLimit(1)
            } else {
                Text(entry.problems.first ?? quietDetail(entry))
                    .font(.subheadline)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(entry.tiles.first?.pin.link)
    }
}

#Preview("Lock Screen", as: .accessoryRectangular) {
    NeedsAttentionWidget()
} timeline: {
    AttentionEntry(date: .now, tiles: [PinTile.samples[4]], instanceCount: 1, checkedAt: .now)
}
#endif

#Preview("Small", as: .systemSmall) {
    NeedsAttentionWidget()
} timeline: {
    AttentionEntry(date: .now, tiles: [PinTile.samples[4], PinTile.samples[2]], instanceCount: 2, checkedAt: .now)
    AttentionEntry(date: .now, tiles: [], instanceCount: 2, checkedAt: .now)
}

#Preview("Medium", as: .systemMedium) {
    NeedsAttentionWidget()
} timeline: {
    AttentionEntry(date: .now, tiles: [PinTile.samples[4], PinTile.samples[2]], instanceCount: 2, checkedAt: .now)
    AttentionEntry(date: .now, tiles: [], instanceCount: 2, checkedAt: .now)
}

#Preview("Large", as: .systemLarge) {
    NeedsAttentionWidget()
} timeline: {
    AttentionEntry(
        date: .now, tiles: [PinTile.samples[4], PinTile.samples[2]], problems: ["Can't reach staging"],
        instanceCount: 3, checkedAt: .now)
}

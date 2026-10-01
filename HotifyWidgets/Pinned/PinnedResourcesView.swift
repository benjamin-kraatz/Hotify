import SwiftUI
import WidgetKit

/// Lays out a Pinned Resources widget for its size: one hero tile, rows, or a grid.
struct PinnedResourcesView: View {
    var entry: PinnedEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let reason = entry.emptyReason {
                PinnedEmptyView(reason: reason)
            } else {
                switch family {
                case .systemSmall:
                    if let tile = entry.tiles.first { PinnedHeroTile(tile: tile) }
                case .systemMedium:
                    switch entry.tiles.count {
                    case 1: PinnedWideHero(tile: entry.tiles[0])
                    case 4: PinnedGrid(tiles: entry.tiles, columns: 2, isCompact: true)
                    default: PinnedRows(tiles: entry.tiles)
                    }
                #if os(iOS)
                case .accessoryRectangular:
                    if let tile = entry.tiles.first { PinnedAccessoryTile(tile: tile) }
                #endif
                default:
                    PinnedGrid(tiles: entry.tiles, columns: 2, isCompact: false)
                }
            }
        }
        .containerBackground(for: .widget) {
            HeatBackdrop(heats: entry.tiles.map(\.heat))
        }
    }
}

/// The small widget: one resource, its flame large.
struct PinnedHeroTile: View {
    var tile: PinTile

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                FlameGlyph(heat: tile.heat, height: 40)
                    .widgetAccentable()
                Spacer(minLength: 4)
                if let primary = tile.primary {
                    ActionButton(tile: tile, action: primary)
                }
            }
            Spacer(minLength: 6)
            Text(tile.name)
                .font(.display(.headline))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            TileStatus(tile: tile, showsAge: true)
                .font(.caption)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(tile.pin.link)
    }
}

/// The medium widget with one resource: its flame large, where it runs, and every action it has.
struct PinnedWideHero: View {
    var tile: PinTile

    var body: some View {
        HStack(spacing: 12) {
            Link(destination: tile.pin.link) {
                HStack(spacing: 16) {
                    FlameGlyph(heat: tile.heat, height: 58)
                        .widgetAccentable()
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tile.name)
                            .font(.display(.title3))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if let subtitle = tile.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        TileStatus(tile: tile, showsAge: true)
                            .font(.caption)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
            }
            VStack(alignment: .trailing, spacing: 6) {
                if tile.isArmed {
                    ActionButton(tile: tile, action: .stop, style: .labeled, width: 100)
                } else {
                    ForEach(tile.actions.prefix(3)) { action in
                        ActionButton(tile: tile, action: action, style: .labeled, width: 100)
                    }
                }
            }
        }
    }
}

/// The medium widget with two or three resources, one row each.
struct PinnedRows: View {
    var tiles: [PinTile]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                if index > 0 {
                    Divider().padding(.leading, 34)
                }
                row(tile)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    /// The link and the button sit side by side. A button nested in a link would leave the tap to chance.
    private func row(_ tile: PinTile) -> some View {
        HStack(spacing: 6) {
            Link(destination: tile.pin.link) {
                HStack(spacing: 12) {
                    FlameGlyph(heat: tile.heat, height: 24)
                        .widgetAccentable()
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tile.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        TileStatus(tile: tile, showsAge: tiles.count == 1)
                            .font(.caption)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
            }
            if let primary = tile.primary {
                ActionButton(tile: tile, action: primary, style: .labeled)
            }
        }
    }
}

/// Resources as tiles: two by two on a medium widget, two by three on a large one.
struct PinnedGrid: View {
    var tiles: [PinTile]
    var columns: Int
    /// Medium tiles have room for one button. Large ones show every action.
    var isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 8 : 10) {
            if !isCompact {
                PinnedHeader(tiles: tiles)
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(rows.indices, id: \.self) { index in
                    GridRow {
                        ForEach(rows[index]) { tile in
                            PinnedGridTile(tile: tile, isCompact: isCompact)
                        }
                        // An odd last row keeps its tile at half width.
                        if rows[index].count < columns {
                            Color.clear.gridCellUnsizedAxes([.vertical])
                        }
                    }
                }
            }
            if !isCompact, tiles.count < 6 {
                Spacer(minLength: 0)
            }
        }
    }

    private var rows: [[PinTile]] {
        stride(from: 0, to: tiles.count, by: columns).map { Array(tiles[$0..<min($0 + columns, tiles.count)]) }
    }
}

/// One resource in the grid.
struct PinnedGridTile: View {
    var tile: PinTile
    var isCompact: Bool

    var body: some View {
        Group {
            // Links and buttons sit side by side. A button nested in a link would leave the tap to chance.
            if isCompact {
                HStack(spacing: 4) {
                    Link(destination: tile.pin.link) {
                        HStack(spacing: 8) {
                            FlameGlyph(heat: tile.heat, height: 22)
                                .widgetAccentable()
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tile.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                TileStatus(tile: tile)
                                    .font(.caption2)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxHeight: .infinity)
                        .contentShape(.rect)
                    }
                    if let primary = tile.primary {
                        ActionButton(tile: tile, action: primary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 4) {
                        Link(destination: tile.pin.link) {
                            FlameGlyph(heat: tile.heat, height: 26)
                                .widgetAccentable()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                        }
                        actions
                    }
                    Link(destination: tile.pin.link) {
                        VStack(alignment: .leading, spacing: 2) {
                            Spacer(minLength: 4)
                            Text(tile.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            TileStatus(tile: tile)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                }
            }
        }
        .padding(isCompact ? 8 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.fill.quinary, in: .rect(cornerRadius: 14))
    }

    /// An armed stop takes the room of every button, so the second tap has a large target.
    @ViewBuilder
    private var actions: some View {
        if tile.isArmed {
            ActionButton(tile: tile, action: .stop)
        } else {
            HStack(spacing: 4) {
                ForEach(tile.actions.prefix(3)) { action in
                    ActionButton(tile: tile, action: action)
                }
            }
        }
    }
}

/// The large widget's head: how many pinned resources run, and when Coolify last answered.
struct PinnedHeader: View {
    var tiles: [PinTile]

    private var running: Int { tiles.filter { $0.heat == .lit }.count }
    private var attention: Int { tiles.filter(\.isAlert).count }
    private var checked: Date? { tiles.compactMap(\.checkedAt).min() }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(running) of \(tiles.count) running")
                .font(.display(.subheadline))
            if attention > 0 {
                Text("\(attention) \(attention == 1 ? "needs" : "need") a look")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.glow)
            }
            Spacer(minLength: 4)
            if let checked {
                Text(
                    .currentDate,
                    format: .reference(to: checked, allowedFields: [.minute, .hour, .day], maxFieldCount: 1)
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
        .lineLimit(1)
    }
}

/// What a widget says before it has anything to show.
struct PinnedEmptyView: View {
    var reason: PinnedEntry.EmptyReason

    @Environment(\.widgetFamily) private var family

    private var isOnLockScreen: Bool {
        #if os(iOS)
        family == .accessoryRectangular
        #else
        false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlameGlyph(heat: .cold, height: isOnLockScreen ? 16 : 30)
            Spacer(minLength: 0)
            Text(reason == .noInstances ? "No instance yet" : "Nothing pinned")
                .font(.headline)
            Text(
                reason == .noInstances
                    ? "Add a Coolify instance in Hotify."
                    : "Edit the widget to pick resources."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

#Preview("Small", as: .systemSmall) {
    PinnedResourcesWidget()
} timeline: {
    PinnedEntry(date: .now, tiles: [PinTile.samples[0]])
    PinnedEntry(date: .now, tiles: [PinTile.samples[3]])
}

#Preview("Medium hero", as: .systemMedium) {
    PinnedResourcesWidget()
} timeline: {
    PinnedEntry(date: .now, tiles: [PinTile.samples[1]])
}

#Preview("Medium rows", as: .systemMedium) {
    PinnedResourcesWidget()
} timeline: {
    PinnedEntry(date: .now, tiles: Array(PinTile.samples.prefix(3)))
}

#Preview("Medium grid", as: .systemMedium) {
    PinnedResourcesWidget()
} timeline: {
    PinnedEntry(date: .now, tiles: Array(PinTile.samples.prefix(4)))
}

#Preview("Large", as: .systemLarge) {
    PinnedResourcesWidget()
} timeline: {
    PinnedEntry(date: .now, tiles: PinTile.samples)
}

#Preview("Empty", as: .systemSmall) {
    PinnedResourcesWidget()
} timeline: {
    PinnedEntry(date: .now, tiles: [], emptyReason: .nothingPinned)
}

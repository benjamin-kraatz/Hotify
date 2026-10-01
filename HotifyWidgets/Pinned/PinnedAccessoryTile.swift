import SwiftUI
import WidgetKit

#if os(iOS)
/// One pinned resource on the Lock Screen: its flame and name, then its status and age.
struct PinnedAccessoryTile: View {
    var tile: PinTile

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                FlameGlyph(heat: tile.heat, height: 14)
                    .widgetAccentable()
                Text(tile.name)
                    .font(.headline)
                    .lineLimit(1)
            }
            Text(tile.status)
                .font(.subheadline)
                .lineLimit(1)
            if let checkedAt = tile.checkedAt {
                Text(
                    .currentDate,
                    format: .reference(to: checkedAt, allowedFields: [.minute, .hour, .day], maxFieldCount: 1)
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(tile.pin.link)
    }
}

#Preview(as: .accessoryRectangular) {
    PinnedResourcesWidget()
} timeline: {
    PinnedEntry(date: .now, tiles: [PinTile.samples[1]])
}
#endif

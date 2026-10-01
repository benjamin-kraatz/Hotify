import SwiftUI

/// A tile's status word, amber when it wants a look, and optionally how long ago Coolify said so.
struct TileStatus: View {
    var tile: PinTile
    var showsAge = false

    var body: some View {
        HStack(spacing: 4) {
            Text(tile.status)
                .foregroundStyle(tile.isAlert ? AnyShapeStyle(.glow) : AnyShapeStyle(.secondary))
            if showsAge, let checkedAt = tile.checkedAt {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(
                    .currentDate,
                    format: .reference(to: checkedAt, allowedFields: [.minute, .hour, .day], maxFieldCount: 1)
                )
                .foregroundStyle(.tertiary)
            }
        }
        .lineLimit(1)
    }
}

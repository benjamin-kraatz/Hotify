import SwiftUI
import WidgetKit

/// One resource as a row: its flame, name, and status, with its most likely action at the end.
///
/// The link and the button sit side by side. A button nested in a link would leave the tap to chance.
struct TileRow: View {
    var tile: PinTile
    var showsAge = false
    /// Names the instance after the status, for lists that span several.
    var showsInstance = false

    var body: some View {
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
                        HStack(spacing: 4) {
                            TileStatus(tile: tile, showsAge: showsAge)
                            if showsInstance, !tile.instanceName.isEmpty {
                                Text("·").foregroundStyle(.tertiary)
                                Text(tile.instanceName)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
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

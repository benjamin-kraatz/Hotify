import AppIntents
import SwiftUI
import WidgetKit

/// A widget button that runs one action on a pinned resource. An armed stop turns amber and asks for the second tap.
struct ActionButton: View {
    var tile: PinTile
    var action: ResourceAction
    var style: ButtonFace.Style = .icon
    /// A fixed width for labeled buttons stacked in a column, so their edges line up.
    var width: CGFloat?

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var isArmed: Bool { action == .stop && tile.isArmed }

    var body: some View {
        Button(intent: ResourceActionIntent(pin: tile.pin, action: action)) {
            if isArmed {
                Text("Stop?")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(renderingMode == .fullColor ? AnyShapeStyle(.background) : AnyShapeStyle(.primary))
                    .padding(.horizontal, 10)
                    .frame(width: width, height: 30)
                    .background(armedFill, in: .capsule)
            } else {
                ButtonFace(
                    title: title, systemImage: action.systemImage, style: style, isKindling: action == .start,
                    width: width)
            }
        }
        .buttonStyle(.plain)
        .widgetAccentable(isArmed)
        .accessibilityLabel(isArmed ? "Confirm stopping \(tile.name)" : "\(action.title) \(tile.name)")
    }

    private var armedFill: AnyShapeStyle {
        renderingMode == .fullColor ? AnyShapeStyle(.glow) : AnyShapeStyle(.fill.secondary)
    }

    /// Short words that fit a row. The app's longer titles are for menus.
    private var title: String {
        switch action {
        case .start: "Start"
        case .deploy: "Deploy"
        case .restart: "Restart"
        case .stop: "Stop"
        case .cancelDeployment: "Cancel"
        }
    }
}

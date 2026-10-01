import SwiftUI
import WidgetKit

/// How a widget button looks: a round icon, or an icon and a word in a capsule.
struct ButtonFace: View {
    var title: String
    var systemImage: String
    var style: Style = .icon
    /// Starting something lights its icon in the brand red.
    var isKindling = false
    /// A fixed width for labeled buttons stacked in a column, so their edges line up.
    var width: CGFloat?

    enum Style {
        /// A round icon, for tiles with little room.
        case icon
        /// An icon and a word, for rows.
        case labeled
    }

    var body: some View {
        switch style {
        case .icon:
            icon
                .frame(width: 30, height: 30)
                .background(.fill.tertiary, in: .circle)
        case .labeled:
            Label {
                Text(title)
            } icon: {
                icon
            }
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10)
            .frame(width: width, height: 30)
            .background(.fill.tertiary, in: .capsule)
        }
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(isKindling ? AnyShapeStyle(.ember) : AnyShapeStyle(.primary))
            .widgetAccentable(isKindling)
    }
}

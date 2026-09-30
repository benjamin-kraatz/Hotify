#if os(macOS)
import SwiftUI

/// The status item. The flame fills once something watched runs, and a number counts what needs a look.
struct MenuBarIcon: View {
    var model: MenuBarModel

    private var attentionCount: Int {
        model.heats.count(where: \.needsAttention)
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: model.heats.contains(.lit) ? "flame.fill" : "flame")
            if attentionCount > 0 {
                Text("\(attentionCount)")
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(attentionCount > 0 ? "Hotify, \(attentionCount) need a look" : "Hotify")
    }
}

#Preview {
    MenuBarIcon(model: MenuBarModel(preview: true))
        .padding()
}
#endif

import SwiftUI

/// The symbol for a compose file someone wrote, on the ember tile a template's logo would sit on.
struct ComposeMark: View {
    var size: CGFloat = 44

    static let systemImage = "square.stack.3d.up.fill"

    var body: some View {
        Image(systemName: Self.systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.ember)
            .frame(width: size, height: size)
            .background(.ember.opacity(0.12), in: .rect(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 16) {
        ComposeMark(size: 40)
        ComposeMark(size: 56)
        ComposeMark(size: 72)
    }
    .padding()
}

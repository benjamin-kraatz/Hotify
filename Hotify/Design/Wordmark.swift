import SwiftUI

/// The small flame and name at the foot of a sidebar.
struct Wordmark: View {
    var body: some View {
        HStack(spacing: 7) {
            FlameGlyph(heat: .lit, height: 15)
            Text("Hotify")
                .font(.display(.subheadline))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hotify")
    }
}

#Preview {
    Wordmark()
        .padding()
}

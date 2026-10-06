import SwiftUI

/// What a screen shows while its first load is out: a small flame that flickers as it catches, with a soft glow
/// under it. A spinner stays for work inside a button or a row.
struct Kindling: View {
    /// A line under the flame, such as `Loading tasks…`. `nil` leaves the flame on its own.
    var caption: String?
    var height: CGFloat = 30

    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false

    var body: some View {
        VStack(spacing: 12) {
            FlameGlyph(heat: .warming, height: height)
                .background {
                    Ellipse()
                        .fill(.glow.opacity(0.22))
                        .frame(width: height * 1.4, height: height * 0.42)
                        .blur(radius: height * 0.22)
                        .offset(y: height * 0.48)
                }
            if let caption {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        // A fast load never shows the flame at all. A slow one fades it in.
        .opacity(isShown ? 1 : 0)
        .scaleEffect(isShown || reduceMotion ? 1 : 0.92, anchor: .bottom)
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.25)) {
                isShown = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption ?? "Loading")
    }
}

#Preview {
    HStack(spacing: 40) {
        Kindling()
        Kindling(caption: "Loading tasks…")
    }
    .frame(width: 480, height: 240)
}

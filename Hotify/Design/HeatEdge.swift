import SwiftUI

extension View {
    /// A rim of fire that circles a panel while something works inside it, and fades once the work is done.
    func heatEdge(isActive: Bool, cornerRadius: CGFloat = 14) -> some View {
        modifier(HeatEdge(isActive: isActive, cornerRadius: cornerRadius))
    }
}

private struct HeatEdge: ViewModifier {
    var isActive: Bool
    var cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let lap: TimeInterval = 2.4
    /// Room around the panel for the rim's glow, which a canvas would otherwise cut off at its bounds.
    private static let bleed: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .overlay {
                // With Reduce Motion the rim stays lit in place instead of circling.
                TimelineView(.animation(paused: !isActive || reduceMotion)) { timeline in
                    let elapsed = timeline.date.timeIntervalSinceReferenceDate
                    let turn = reduceMotion ? 0 : elapsed.truncatingRemainder(dividingBy: Self.lap) / Self.lap
                    // Drawn, not built from shapes. An animation elsewhere in the panel reaches an animatable
                    // gradient angle and makes the rim strobe.
                    Canvas { context, size in
                        let panel = CGRect(origin: .zero, size: size).insetBy(dx: Self.bleed, dy: Self.bleed)
                        let path = Path(roundedRect: panel.insetBy(dx: 0.75, dy: 0.75), cornerRadius: cornerRadius)
                        let ember = Color.ember
                        let fire = GraphicsContext.Shading.conicGradient(
                            Gradient(colors: [ember.opacity(0), ember, .glow, .core, .glow, ember.opacity(0)]),
                            center: CGPoint(x: panel.midX, y: panel.midY),
                            angle: .degrees(turn * 360)
                        )
                        var glow = context
                        glow.addFilter(.blur(radius: 5))
                        glow.stroke(path, with: fire, lineWidth: 2)
                        context.stroke(path, with: fire, lineWidth: 1.5)
                    }
                    .padding(-Self.bleed)
                }
                .opacity(isActive ? 1 : 0)
                .animation(.easeInOut(duration: 0.6), value: isActive)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }
}

#Preview {
    @Previewable @State var isActive = true
    Toggle("Working", isOn: $isActive)
        .padding(24)
        .well()
        .heatEdge(isActive: isActive)
        .padding(40)
}

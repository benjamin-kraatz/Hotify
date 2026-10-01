import SwiftUI

/// One tick per resource, sorted hot to cold, so a glance tells how much of an instance is up.
struct HeatStrip: View {
    var heats: [Heat]
    /// A fixed tick width for small inline strips. Leave it `nil` to stretch the ticks across the row.
    var tickWidth: CGFloat?
    var height: CGFloat = 10

    @SwiftUI.Environment(\.backgroundProminence) private var prominence

    private var sorted: [Heat] { heats.sorted() }

    var body: some View {
        HStack(spacing: height >= 8 ? 3 : 2) {
            ForEach(Array(sorted.enumerated()), id: \.offset) { _, heat in
                Capsule()
                    .fill(fill(for: heat))
                    .frame(width: tickWidth, height: height)
                    .frame(maxWidth: tickWidth == nil ? .infinity : nil)
            }
        }
        .animation(.smooth(duration: 0.5), value: sorted)
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    private func fill(for heat: Heat) -> AnyShapeStyle {
        // On a selected row the accent fill matches the lit color, so ticks go white and fade by heat.
        if prominence == .increased {
            switch heat {
            case .lit: return AnyShapeStyle(.white)
            case .warming, .troubled: return AnyShapeStyle(.glow)
            case .cold, .unknown: return AnyShapeStyle(.white.opacity(0.35))
            }
        }
        switch heat {
        case .lit: return AnyShapeStyle(.ember)
        case .warming, .troubled: return AnyShapeStyle(.glow)
        case .cold, .unknown: return AnyShapeStyle(.quaternary)
        }
    }

    private var accessibilitySummary: String {
        let running = heats.filter { $0 == .lit }.count
        let attention = heats.filter(\.needsAttention).count
        var summary = "\(running) of \(heats.count) running"
        if attention > 0 {
            summary += ", \(attention) need attention"
        }
        return summary
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        HeatStrip(heats: [.lit, .cold, .lit, .troubled, .cold, .lit, .warming, .cold, .lit])
        HeatStrip(heats: [.lit, .lit, .cold], tickWidth: 4, height: 6)
    }
    .frame(width: 320)
    .padding()
}

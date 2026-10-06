import SwiftUI

/// One tick per recent run, oldest on the left, so a streak of failures shows before you read a row. The newest
/// tick stands a little taller, and a run in flight glows on the right as it works.
struct RunStrip: View {
    /// Newest first, the order Coolify lists runs in.
    var heats: [Heat]
    /// Says how the runs went, such as `4 of the last 5 backed up`.
    var summary: String
    var limit = 30

    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Oldest first, keyed from the newest so a new run slides the rest left instead of redrawing every tick.
    private var ticks: [(key: Int, heat: Heat)] {
        let recent = Array(heats.prefix(limit))
        return recent.enumerated().reversed().map { (key: recent.count - $0.offset, heat: $0.element) }
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(ticks, id: \.key) { tick in
                    let isNewest = tick.key == heats.prefix(limit).count
                    RunTick(heat: tick.heat, height: isNewest ? 16 : 12)
                        .transition(
                            reduceMotion
                                ? .opacity : .scale(scale: 0.2, anchor: .bottom).combined(with: .opacity))
                }
            }
            .frame(height: 16, alignment: .bottom)
            Text(summary)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .lineLimit(1)
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.3), value: heats)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }
}

private struct RunTick: View {
    var heat: Heat
    var height: CGFloat

    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Capsule()
            .fill(fill)
            .frame(width: 5, height: height)
            .keyframeAnimator(initialValue: 1.0, repeating: heat == .warming && !reduceMotion) { tick, opacity in
                tick.opacity(opacity)
            } keyframes: { _ in
                KeyframeTrack(\.self) {
                    CubicKeyframe(0.4, duration: 0.6)
                    CubicKeyframe(1.0, duration: 0.6)
                }
            }
    }

    private var fill: AnyShapeStyle {
        switch heat {
        case .lit: AnyShapeStyle(.ember)
        case .warming, .troubled: AnyShapeStyle(.glow)
        case .cold, .unknown: AnyShapeStyle(.quaternary)
        }
    }
}

extension RunStrip {
    /// `good of the last count verb`, counting lit runs, such as `4 of the last 5 backed up`.
    init(heats: [Heat], verb: String, limit: Int = 30) {
        let recent = heats.prefix(limit)
        let good = recent.count { $0 == .lit }
        self.init(heats: heats, summary: "\(good) of the last \(recent.count) \(verb)", limit: limit)
    }
}

#Preview {
    @Previewable @State var heats: [Heat] = [.troubled, .lit, .lit, .lit, .troubled, .lit, .lit, .lit]
    VStack(alignment: .leading, spacing: 20) {
        RunStrip(heats: heats, verb: "backed up")
        RunStrip(heats: [.warming, .lit, .lit], verb: "finished")
        Button("New run") { heats.insert([.lit, .troubled].randomElement()!, at: 0) }
    }
    .padding(30)
}

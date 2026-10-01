import SwiftUI

/// The status mark. A lit flame is the logo, a cold one is its outline, and amber means look here.
///
/// Lighting up plays a short flare. Warming flickers until it settles. Both stay still with Reduce Motion on.
/// A preview burns blue, and while it builds its core flickers amber inside the blue.
struct FlameGlyph: View {
    var heat: Heat
    /// The glyph's height. Its width follows the logo's proportions.
    var height: CGFloat = 18
    /// Starts cold and lights up once the glyph is on screen, if it is lit.
    var ignitesOnAppear = false
    var tone: FlameTone = .production
    /// A lit core that swells and settles slowly, like a pilot light. For the one large flame that heads a screen.
    var breathes = false

    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SwiftUI.Environment(\.backgroundProminence) private var prominence
    @State private var isKindled = false
    @State private var flares = 0

    private var shown: Heat {
        ignitesOnAppear && !isKindled && heat == .lit ? .cold : heat
    }

    private var isHollow: Bool {
        shown == .cold || shown == .unknown
    }

    private var hasCore: Bool {
        shown == .lit || shown == .warming
    }

    /// A selected row is filled with the accent, which is the same red as a lit flame. Invert there.
    private var isOnAccent: Bool {
        prominence == .increased
    }

    private var bodyColor: Color {
        if isOnAccent {
            return .white
        }
        switch (shown, tone) {
        case (.lit, _): return tone.fill
        // A building preview keeps its blue, so it still reads as a preview while the core says it is busy.
        case (.warming, .preview): return .pilot
        default: return .glow
        }
    }

    private var coreColor: Color {
        if isOnAccent {
            return shown == .warming ? .glow : tone.fill
        }
        if shown == .warming {
            return tone == .preview ? .glow : .white.opacity(0.9)
        }
        return tone.core
    }

    private var isBreathing: Bool {
        breathes && shown == .lit && !reduceMotion
    }

    private var width: CGFloat { height / 1.5 }

    private var lineWidth: CGFloat { max(1.2, height / 14) }

    var body: some View {
        ZStack(alignment: .bottom) {
            FlameShape()
                .stroke(
                    isOnAccent ? Color.white.opacity(0.8) : Color.secondary,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineJoin: .round,
                        dash: shown == .unknown ? [lineWidth * 1.6, lineWidth * 1.4] : []
                    )
                )
                .padding(lineWidth / 2)
                .opacity(isHollow ? 1 : 0)

            FlameShape()
                .fill(bodyColor)
                .scaleEffect(isHollow ? 0.5 : 1, anchor: .bottom)
                .opacity(isHollow ? 0 : 1)

            core

            if shown == .troubled {
                Image(systemName: "exclamationmark")
                    .font(.system(size: height * 0.42, weight: .black))
                    .foregroundStyle(isOnAccent ? AnyShapeStyle(Color.glow) : AnyShapeStyle(.background))
                    .padding(.bottom, height * 0.1)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .frame(width: width, height: height)
        .keyframeAnimator(initialValue: 1.0, trigger: flares) { content, scale in
            content.scaleEffect(scale, anchor: .bottom)
        } keyframes: { _ in
            KeyframeTrack(\.self) {
                SpringKeyframe(1.22, duration: 0.16)
                SpringKeyframe(0.94, duration: 0.2)
                SpringKeyframe(1.0, duration: 0.3)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.3), value: shown)
        .onChange(of: heat) { old, new in
            if new == .lit, old != .lit, !reduceMotion {
                flares += 1
            }
        }
        .task {
            guard ignitesOnAppear, !isKindled else { return }
            try? await Task.sleep(for: .milliseconds(180))
            isKindled = true
            if heat == .lit, !reduceMotion {
                flares += 1
            }
        }
        .accessibilityHidden(true)
    }

    private var core: some View {
        FlameShape()
            .fill(coreColor)
            .frame(width: width * 0.53, height: height * 0.56)
            .keyframeAnimator(initialValue: 1.0, repeating: shown == .warming && !reduceMotion) { content, scale in
                content.scaleEffect(scale, anchor: .bottom)
            } keyframes: { _ in
                // Uneven steps read as a flicker rather than a metronome.
                KeyframeTrack(\.self) {
                    CubicKeyframe(0.72, duration: 0.3)
                    CubicKeyframe(0.96, duration: 0.22)
                    CubicKeyframe(0.8, duration: 0.26)
                    CubicKeyframe(1.0, duration: 0.32)
                }
            }
            .keyframeAnimator(initialValue: 1.0, repeating: isBreathing) { content, scale in
                content.scaleEffect(scale, anchor: .bottom)
            } keyframes: { _ in
                // Slow and even, so it reads as idling rather than working.
                KeyframeTrack(\.self) {
                    CubicKeyframe(0.82, duration: 1.6)
                    CubicKeyframe(1.0, duration: 1.8)
                }
            }
            .padding(.bottom, height * 0.07)
            .scaleEffect(hasCore ? 1 : 0.01, anchor: .bottom)
            .opacity(hasCore ? 1 : 0)
    }
}

#Preview("States") {
    HStack(spacing: 28) {
        ForEach([Heat.lit, .warming, .troubled, .cold, .unknown], id: \.self) { heat in
            FlameGlyph(heat: heat, height: 48)
        }
    }
    .padding(40)
}

#Preview("Preview tone") {
    HStack(spacing: 28) {
        ForEach([Heat.lit, .warming, .troubled, .cold], id: \.self) { heat in
            FlameGlyph(heat: heat, height: 48, tone: .preview)
        }
        FlameGlyph(heat: .lit, height: 48, tone: .preview, breathes: true)
    }
    .padding(40)
}

#Preview("Toggle") {
    @Previewable @State var heat = Heat.cold
    VStack(spacing: 24) {
        FlameGlyph(heat: heat, height: 72)
        Picker("Heat", selection: $heat) {
            Text("Lit").tag(Heat.lit)
            Text("Warming").tag(Heat.warming)
            Text("Troubled").tag(Heat.troubled)
            Text("Cold").tag(Heat.cold)
        }
        .pickerStyle(.segmented)
    }
    .padding(40)
}

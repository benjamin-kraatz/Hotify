import SwiftUI

/// A small flare and rising embers when the About flame is stoked.
struct AboutFlame: View {
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ignition = 0

    private struct Flare {
        var heat = 0.0
        var rise = 0.0
        var embers = 0.0
    }

    var body: some View {
        // Animation rendering is nonisolated; capture environment and asset values on the main actor.
        let motionIsReduced = reduceMotion
        let coreColor = Color.core
        let emberColor = Color.ember
        let glowColor = Color.glow
        let coreShape = FlameShape()

        Button {
            ignition += 1
        } label: {
            Color.clear
                .frame(width: 88, height: 88)
                .keyframeAnimator(initialValue: Flare(), trigger: ignition) { _, flare in
                    ZStack {
                        FlameGlyph(heat: .lit, height: 88)
                            .overlay(alignment: .bottom) {
                                coreShape
                                    .fill(coreColor)
                                    .frame(width: 24, height: 54)
                                    .blur(radius: 5)
                                    .padding(.bottom, 6)
                                    .opacity(flare.heat * 0.7)
                            }
                            .scaleEffect(
                                x: 1 - (motionIsReduced ? 0 : flare.heat * 0.06),
                                y: 1 + (motionIsReduced ? 0 : flare.heat * 0.13),
                                anchor: .bottom
                            )
                            .shadow(color: emberColor.opacity(0.18 + flare.heat * 0.3), radius: 24, y: 8)
                            .shadow(color: glowColor.opacity(flare.heat * 0.3), radius: 12)

                        if !motionIsReduced {
                            ForEach(0..<6) { index in
                                let side = index.isMultiple(of: 2) ? -1.0 : 1.0
                                let spread = Double(index / 2 + 1)
                                Capsule()
                                    .fill(index.isMultiple(of: 2) ? coreColor : glowColor)
                                    .frame(width: 2, height: 3 + spread)
                                    .rotationEffect(.degrees(side * flare.rise * 25))
                                    .offset(
                                        x: side * (3 + spread * 4 * flare.rise),
                                        y: -12 - flare.rise * (34 + spread * 7)
                                    )
                                    .opacity(flare.embers * (1 - flare.rise * 0.5))
                                    .blur(radius: flare.rise * 0.5)
                            }
                        }
                    }
                    .frame(width: 88, height: 88)
                } keyframes: { _ in
                    KeyframeTrack(\.heat) {
                        CubicKeyframe(1, duration: 0.18)
                        CubicKeyframe(0, duration: 1.0)
                    }
                    KeyframeTrack(\.rise) {
                        LinearKeyframe(0, duration: 0.01)
                        CubicKeyframe(1, duration: 1.17)
                    }
                    KeyframeTrack(\.embers) {
                        LinearKeyframe(0, duration: 0.06)
                        LinearKeyframe(1, duration: 0.12)
                        CubicKeyframe(0, duration: 1.0)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stoke the flame")
        .accessibilityHint("Makes the flame burn a little brighter")
        .help("Stoke the flame")
    }
}

#Preview {
    AboutFlame()
        .padding(60)
}

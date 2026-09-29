import SwiftUI

/// The logo flame, lit, that catches fire when touched. Tap it and tongues of fire pull up out of it. Hold it and it
/// keeps burning.
///
/// With Reduce Motion on, the flame stays put and only glows hotter.
struct StokableFlame: View {
    /// The flame's height. Its width follows the logo's proportions, and the fire scales with it.
    var height: CGFloat
    /// Extra room the layout keeps above the flame for the fire. The fire reaches past it, so this only needs to
    /// cover what the surrounding views would otherwise clip.
    var headroom: CGFloat = 0
    /// Flares once on its own shortly after the flame appears.
    var ignitesOnAppear = false

    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stokes = StokeHistory()
    /// When the fire goes out. Nil while it is cold, so the timeline stops drawing.
    @State private var burnsUntil: Date?
    /// Set when a pointer or touch press stoked the fire, so the button action that follows does not stoke it twice.
    @State private var pressStoked = false
    @State private var presses = 0
    @State private var hasIgnited = false

    var body: some View {
        let renderer = FireRenderer(
            stokes: stokes,
            palette: FireRenderer.Palette(ember: .ember, core: .core, hot: Color.core.mix(with: .white, by: 0.55)),
            reduceMotion: reduceMotion
        )
        let canvas = FireRenderer.canvasSize(flameHeight: height)
        let flameHeight = height

        Button {
            if pressStoked {
                pressStoked = false
            } else {
                tap()
                presses += 1
            }
        } label: {
            // The canvas reaches past the layout frame, up for the fire and down for the glow, so the flame sits
            // where a `FlameGlyph` of the same height would.
            Color.clear
                .frame(width: height / 1.5, height: height + headroom)
                .overlay(alignment: .bottom) {
                    TimelineView(.animation(paused: burnsUntil == nil)) { timeline in
                        Canvas { context, size in
                            renderer.draw(
                                in: &context,
                                size: size,
                                flameHeight: flameHeight,
                                time: timeline.date.timeIntervalSinceReferenceDate
                            )
                        }
                    }
                    .frame(width: canvas.width, height: canvas.height)
                    .offset(y: FireRenderer.floor(flameHeight: height))
                    .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(StokeButtonStyle(onPress: pressChanged))
        .sensoryFeedback(.impact(weight: .light), trigger: presses)
        .task(id: burnsUntil) {
            guard let burnsUntil, burnsUntil != .distantFuture else { return }
            do {
                try await Task.sleep(for: .seconds(max(0, burnsUntil.timeIntervalSinceNow)))
                self.burnsUntil = nil
                stokes = StokeHistory()
            } catch {}
        }
        .task {
            guard ignitesOnAppear, !hasIgnited else { return }
            do {
                try await Task.sleep(for: .milliseconds(180))
                hasIgnited = true
                tap()
            } catch {}
        }
        .accessibilityLabel("Stoke the flame")
        .accessibilityHint("Makes the flame flare up")
        .help("Stoke the flame")
    }

    private func tap() {
        let now = Date.now
        stokes.tap(at: now.timeIntervalSinceReferenceDate)
        burn(until: now + StokeHistory.afterglow)
    }

    private func pressChanged(_ isPressed: Bool) {
        let now = Date.now
        if isPressed {
            pressStoked = true
            stokes.begin(at: now.timeIntervalSinceReferenceDate)
            presses += 1
            burn(until: .distantFuture)
        } else {
            stokes.end(at: now.timeIntervalSinceReferenceDate)
            burn(until: now + StokeHistory.afterglow)
        }
    }

    private func burn(until date: Date) {
        // A press still held keeps the fire going, whatever ends before it.
        burnsUntil = stokes.isHeld ? .distantFuture : date
    }
}

/// Reports when the flame is pressed and let go, so holding it can keep the fire fed.
private struct StokeButtonStyle: ButtonStyle {
    var onPress: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, isPressed in
                onPress(isPressed)
            }
    }
}

#Preview("About") {
    StokableFlame(height: 88, headroom: 24)
        .padding(60)
}

#Preview("Welcome") {
    StokableFlame(height: 128, ignitesOnAppear: true)
        .padding(90)
}

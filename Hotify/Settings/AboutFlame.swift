import SwiftUI

/// The About flame. Tap it and it flares, tongues of fire pulling up out of the logo. Hold it and it keeps burning.
///
/// With Reduce Motion on, the flame stays put and only glows hotter.
struct AboutFlame: View {
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stokes = StokeHistory()
    /// When the fire goes out. Nil while it is cold, so the timeline stops drawing.
    @State private var burnsUntil: Date?
    /// Set when a pointer or touch press stoked the fire, so the button action that follows does not stoke it twice.
    @State private var pressStoked = false
    @State private var presses = 0

    var body: some View {
        let renderer = FireRenderer(
            stokes: stokes,
            palette: FireRenderer.Palette(ember: .ember, core: .core, hot: Color.core.mix(with: .white, by: 0.55)),
            reduceMotion: reduceMotion
        )

        Button {
            if pressStoked {
                pressStoked = false
            } else {
                stokes.tap(at: Date.now.timeIntervalSinceReferenceDate)
                presses += 1
                burn(until: .now + StokeHistory.afterglow)
            }
        } label: {
            // The layout keeps a little headroom for the fire. The canvas reaches further, into the padding above
            // and the gap below, so the flame sits where it always has.
            Color.clear
                .frame(width: 88, height: 112)
                .overlay(alignment: .bottom) {
                    TimelineView(.animation(paused: burnsUntil == nil)) { timeline in
                        Canvas { context, size in
                            renderer.draw(in: &context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
                        }
                    }
                    .frame(width: FireRenderer.size.width, height: FireRenderer.size.height)
                    .offset(y: FireRenderer.floor)
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
        .accessibilityLabel("Stoke the flame")
        .accessibilityHint("Makes the flame flare up")
        .help("Stoke the flame")
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

#Preview {
    AboutFlame()
        .padding(60)
}

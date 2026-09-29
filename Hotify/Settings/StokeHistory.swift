import Foundation

/// Every press on the About flame, and how hot they leave it at any moment.
///
/// Heat is a pure function of time, so the fire can be redrawn for any frame without keeping a simulation running.
/// A tap flares and cools off over a couple of seconds. Holding on feeds the fire until it lets go.
nonisolated struct StokeHistory: Sendable {
    struct Press: Sendable {
        var start: TimeInterval
        var end: TimeInterval?
    }

    /// How long the fire keeps burning after the last press lets go.
    static let afterglow: TimeInterval = 6

    private(set) var presses: [Press] = []

    private static let cooling = 1.1
    private static let flare = 0.55
    private static let feed = 1.4
    /// A hold only starts to feed the fire once it is clearly not a tap.
    private static let holdDelay = 0.2

    var isHeld: Bool {
        presses.contains { $0.end == nil }
    }

    mutating func begin(at time: TimeInterval) {
        presses.append(Press(start: time))
    }

    mutating func end(at time: TimeInterval) {
        for index in presses.indices where presses[index].end == nil {
            presses[index].end = time
        }
    }

    mutating func tap(at time: TimeInterval) {
        presses.append(Press(start: time, end: time))
    }

    /// From 0, cold, toward 1, a blaze. It never quite reaches 1, however hard the fire is stoked.
    func heat(at time: TimeInterval) -> Double {
        var fuel = 0.0
        for press in presses where time >= press.start {
            let age = time - press.start
            fuel += Self.flare * (1 - exp(-age / 0.07)) * exp(-age / Self.cooling)

            let letGo = min(time, press.end ?? time)
            let held = letGo - press.start - Self.holdDelay
            if held > 0 {
                let fed = Self.feed * Self.cooling * (1 - exp(-held / Self.cooling))
                fuel += fed * exp(-(time - letGo) / Self.cooling)
            }
        }
        return 1 - exp(-1.3 * fuel)
    }
}

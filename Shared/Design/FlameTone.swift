import SwiftUI

/// Which fire a flame belongs to.
///
/// Production burns in the brand red. A pull request preview burns blue, like a pilot light: a small flame kept going
/// on the side. Amber still means look here in both, so a failing preview glows the same as a failing app.
enum FlameTone: Hashable {
    case production
    case preview

    /// The body of a lit flame, and the color for text and marks that stand for this fire.
    var fill: Color {
        switch self {
        case .production: .ember
        case .preview: .pilot
        }
    }

    /// The core of a lit flame.
    var core: Color {
        switch self {
        case .production: .core
        case .preview: .pilotCore
        }
    }

    /// The color for text that names a heat in this fire. Only lit takes the tone. Everything else reads as usual.
    func tint(for heat: Heat) -> Color {
        heat == .lit ? fill : heat.tint
    }
}

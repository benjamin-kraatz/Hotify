import SwiftUI

extension View {
    /// Liquid Glass buttons where the OS has them, and bordered buttons on iOS 18.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                // An inherited tint fills glass solid. Plain glass should stay clear with a primary label.
                buttonStyle(.glass)
                    .tint(nil)
            }
        } else {
            if prominent {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered)
            }
        }
    }
}

import SwiftUI

extension View {
    /// The soft inset panel that lists, logs, and cards sit in.
    func well(cornerRadius: CGFloat = 14) -> some View {
        background(Color.primary.opacity(0.045), in: .rect(cornerRadius: cornerRadius))
    }
}

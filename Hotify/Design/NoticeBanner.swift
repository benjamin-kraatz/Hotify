import SwiftUI

/// An inline message for a failed load or action, or for a write that went through. A problem is amber, because
/// Hotify keeps red for things that run. Done is lit, in the brand red, like a flame that caught.
struct NoticeBanner: View {
    var message: String
    var tone: Tone = .problem
    /// `nil` picks the tone's own symbol.
    var systemImage: String?

    enum Tone {
        case problem
        case done

        fileprivate var color: Color {
            switch self {
            case .problem: .glow
            case .done: .ember
            }
        }

        fileprivate var systemImage: String {
            switch self {
            case .problem: "exclamationmark.triangle.fill"
            case .done: "checkmark.circle.fill"
            }
        }
    }

    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrivals = 0

    var body: some View {
        Label {
            // Not fixed to its full height. The Mac sizes the window's minimum at the narrowest width, where a
            // fixed text wraps word by word and grows the window past the screen. A stack still gives it every line.
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .contentTransition(.opacity)
        } icon: {
            Image(systemName: systemImage ?? tone.systemImage)
                .foregroundStyle(tone.color)
                .symbolEffect(.bounce, value: arrivals)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(tone.color.opacity(0.12), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(tone.color.opacity(0.18), lineWidth: 1)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .task(id: message) {
            guard !reduceMotion else { return }
            arrivals += 1
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        NoticeBanner(message: "The server did not answer in time. Check that the instance is online.")
        NoticeBanner(message: "Cleanup settings saved.", tone: .done)
    }
    .padding()
}

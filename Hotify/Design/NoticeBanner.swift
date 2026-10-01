import SwiftUI

/// An inline message for a failed load or action. Amber, because Hotify keeps red for things that run.
struct NoticeBanner: View {
    var message: String
    var systemImage = "exclamationmark.triangle.fill"

    var body: some View {
        Label {
            // Not fixed to its full height. The Mac sizes the window's minimum at the narrowest width, where a
            // fixed text wraps word by word and grows the window past the screen. A stack still gives it every line.
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.glow)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.glow.opacity(0.12), in: .rect(cornerRadius: 12))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

#Preview {
    NoticeBanner(message: "The server did not answer in time. Check that the instance is online.")
        .padding()
}

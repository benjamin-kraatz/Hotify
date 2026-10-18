import SwiftUI

/// Says the compose file changed in Coolify while the user edited theirs, and lets them pick which one stays.
struct ComposeConflictNotice: View {
    var isSaving: Bool
    /// Saves the user's file over the one in Coolify.
    var onReplace: () -> Void
    /// Drops the user's compose edits for the one in Coolify.
    var onTakeTheirs: () -> Void

    @State private var isConfirmingDiscard = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            FlameGlyph(heat: .troubled, height: 26)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 8) {
                Text("The compose file changed in Coolify")
                    .font(.headline)
                Text(
                    "Someone saved a different file after you started editing. Saving yours replaces theirs, and using theirs drops your compose edits."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { buttons }
                    VStack(alignment: .leading, spacing: 8) { buttons }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.glow.opacity(0.12), in: .rect(cornerRadius: 14))
        .transition(.move(edge: .top).combined(with: .opacity))
        .confirmationDialog(
            "Drop your compose edits?", isPresented: $isConfirmingDiscard, titleVisibility: .visible
        ) {
            Button("Use Theirs", role: .destructive, action: onTakeTheirs)
        } message: {
            Text("Your other unsaved settings stay.")
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button("Save Mine Anyway", action: onReplace)
            .glassButton()
            .disabled(isSaving)
            .help("Replace the file in Coolify with yours")
        Button("Use Theirs") { isConfirmingDiscard = true }
            .glassButton()
            .disabled(isSaving)
            .help("Drop your compose edits and take the file in Coolify")
    }
}

#Preview {
    ComposeConflictNotice(isSaving: false, onReplace: {}, onTakeTheirs: {})
        .padding()
        .frame(width: 560)
}

import SwiftUI

/// Says a change waits for a restart or redeploy, with the button that does it.
struct ApplyBar: View {
    var kind: ResourceKind
    var message: String
    var action: ResourceAction?
    var isBusy: Bool
    var onApply: (ResourceAction) -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.ember)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let action {
                Button(action.title) {
                    onApply(action)
                }
                .glassButton()
                .disabled(isBusy)
                .help(action.explanation(for: kind))
            }
            Button("Dismiss", systemImage: "xmark") {
                onDismiss()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ember.opacity(0.08), in: .rect(cornerRadius: 12))
    }
}

#Preview {
    VStack(spacing: 12) {
        ApplyBar(
            kind: .application,
            message: "Saved. It takes effect after a redeploy.",
            action: .deploy,
            isBusy: false,
            onApply: { _ in },
            onDismiss: {}
        )
        ApplyBar(
            kind: .database,
            message: "Saved. It takes effect on the next start.",
            action: nil,
            isBusy: false,
            onApply: { _ in },
            onDismiss: {}
        )
    }
    .padding()
    .frame(width: 520)
}

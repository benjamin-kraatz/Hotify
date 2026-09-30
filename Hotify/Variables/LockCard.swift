import SwiftUI

/// The call to unlock, above a locked list.
struct LockCard: View {
    var method: UnlockMethod
    var failure: String?
    var isAuthenticating: Bool
    /// What unlocking is for, shown until an attempt fails.
    var prompt = "Confirm it’s you to see and change them."
    var onUnlock: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.ember)
                .frame(width: 40, height: 40)
                .background(.ember.opacity(0.12), in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Values are locked")
                    .font(.headline)
                Text(failure ?? prompt)
                    .font(.callout)
                    .foregroundStyle(failure == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.glow))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onUnlock) {
                Label("Unlock", systemImage: method.systemImage)
            }
            .glassButton(prominent: true)
            .disabled(isAuthenticating || method == .unavailable)
            .accessibilityLabel("Unlock with \(method.title)")
            .help("Unlock with \(method.titleWithFallback)")
        }
        .padding(14)
        .well()
    }
}

#Preview {
    VStack(spacing: 12) {
        LockCard(method: .touchID, failure: nil, isAuthenticating: false, onUnlock: {})
        LockCard(method: .touchID, failure: "That didn’t match. Try again.", isAuthenticating: false, onUnlock: {})
    }
    .padding()
    .frame(width: 520)
}

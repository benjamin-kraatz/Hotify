import CoolifyAPI
import SwiftUI

/// The confirmation for deleting one application, database, or service. It stays over the resource. Volume deletion
/// stays off until the switch is turned on.
struct ResourceRemovalDialog: View {
    var name: String
    var isDeleting: Bool
    var error: String?
    var onDelete: (RemovalOptions) -> Void
    var onCancel: () -> Void

    @State private var configurations = true
    @State private var volumes = false
    @State private var dockerCleanup = false
    @State private var connectedNetworks = false
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete \(name)?")
                .font(.headline)

            Text("Coolify deletes \(name).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Delete configurations", isOn: $configurations)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Delete volumes", isOn: $volumes)
                    Text("The data in those volumes goes away.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Docker cleanup", isOn: $dockerCleanup)
                Toggle("Delete connected networks", isOn: $connectedNetworks)
            }
            .disabled(isDeleting)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.glow)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isDeleting)
                Button(role: .destructive, action: confirm) {
                    if isDeleting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Delete")
                    }
                }
                .disabled(isDeleting)
            }
        }
        .padding(20)
        .frame(minWidth: 320, idealWidth: 380, maxWidth: 440, alignment: .leading)
        .interactiveDismissDisabled(isDeleting)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        #if os(macOS)
        .presentationSizing(.fitted)
        #endif
        .animation(reduceMotion ? nil : .snappy, value: volumes)
        .animation(reduceMotion ? nil : .snappy, value: error)
    }

    private func confirm() {
        onDelete(
            RemovalOptions(
                configurations: configurations,
                volumes: volumes,
                dockerCleanup: dockerCleanup,
                connectedNetworks: connectedNetworks
            )
        )
    }
}

#Preview("Delete a resource") {
    ResourceRemovalDialog(name: "marketing-site", isDeleting: false, error: nil, onDelete: { _ in }, onCancel: {})
}

#Preview("Coolify refused") {
    ResourceRemovalDialog(
        name: "marketing-site",
        isDeleting: false,
        error: "The environment still has resources.",
        onDelete: { _ in },
        onCancel: {}
    )
}

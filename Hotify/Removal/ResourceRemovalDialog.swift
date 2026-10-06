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
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.wiggle, value: isDeleting)
                    .frame(width: 40, height: 40)
                    .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 11, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Delete \(name)?")
                        .font(.headline)
                        .lineLimit(2)
                    Text(isDeleting ? "Coolify is deleting it…" : "Coolify deletes \(name). This can't be undone.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                option("Delete configurations", systemImage: "doc.badge.gearshape", isOn: $configurations)
                Divider().padding(.leading, 40)
                option("Delete volumes", systemImage: "externaldrive", isOn: $volumes)
                if volumes {
                    Label("The data in those volumes goes away.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.glow)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 40)
                        .padding(.trailing, 12)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Divider().padding(.leading, 40)
                option("Docker cleanup", systemImage: "eraser", isOn: $dockerCleanup)
                Divider().padding(.leading, 40)
                option("Delete connected networks", systemImage: "network", isOn: $connectedNetworks)
            }
            .well(cornerRadius: 12)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.glow.opacity(volumes ? 0.45 : 0), lineWidth: 1)
            }
            .disabled(isDeleting)

            if let error {
                NoticeBanner(message: error)
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

    private func option(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
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

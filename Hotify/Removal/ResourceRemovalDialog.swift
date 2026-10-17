import CoolifyAPI
import SwiftUI

/// The confirmation for deleting one application, database, or service. It stays over the resource, as a popover on
/// the Mac and a short sheet on an iPhone. Volume deletion stays off until the switch is turned on, and Delete asks
/// for Face ID, Touch ID, or the passcode before anything is sent.
struct ResourceRemovalDialog: View {
    var name: String
    var status: RemovalStatus
    var method: UnlockMethod = .current()
    var onDelete: (RemovalOptions) -> Void
    var onCancel: () -> Void

    @State private var configurations = true
    @State private var volumes = false
    @State private var dockerCleanup = false
    @State private var connectedNetworks = false
    @ScaledMetric private var iconWell: CGFloat = 40
    @ScaledMetric private var glyphWidth: CGFloat = 18
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isDeleting: Bool { status == .deleting }
    private var isConfirming: Bool { status == .confirming }
    /// Without a passcode nothing can confirm the owner, so Delete waits until one is set.
    private var canDelete: Bool { !status.isBusy && method != .unavailable }

    private var headerSymbol: String {
        isConfirming ? method.systemImage : "trash.fill"
    }

    private var summary: String {
        switch status {
        case .confirming: "Waiting for \(method.promptName). Nothing is sent until you confirm."
        case .deleting: "Coolify is deleting \(name)…"
        case .ready, .cancelled, .problem: "Coolify deletes \(name). This can't be undone."
        }
    }

    /// What the buttons do right now, under the switches.
    private var footnote: String {
        if method == .unavailable {
            return "Set a \(UnlockMethod.secretName) on this \(UnlockMethod.deviceName) to delete from Hotify."
        }
        switch status {
        case .confirming: return "Cancel withdraws it before anything is sent."
        case .deleting: return "Cancel can't stop it now."
        case .ready, .cancelled, .problem: return "Delete asks for \(method.promptName) first."
        }
    }

    /// What VoiceOver hears when the state moves on, since the text changes under the focused button.
    private var announcement: String? {
        switch status {
        case .ready: nil
        case .confirming: "Waiting for \(method.promptName)"
        case .deleting: "Deleting \(name)"
        case .cancelled: "Cancelled. Nothing was deleted."
        case .problem(let message): message
        }
    }

    var body: some View {
        content
            .interactiveDismissDisabled(isDeleting)
            #if os(macOS)
        .presentationSizing(.fitted)
            #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(isDeleting ? .hidden : .visible)
            #endif
            .animation(reduceMotion ? nil : .snappy, value: volumes)
            .animation(reduceMotion ? nil : .snappy, value: status)
            .onChange(of: status) { _, _ in
                if let announcement {
                    AccessibilityNotification.Announcement(announcement).post()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        form
            .padding(20)
            .frame(minWidth: 320, idealWidth: 380, maxWidth: 440, alignment: .leading)
        #else
        ScrollView {
            form
                .padding(20)
        }
        .scrollBounceBehavior(.basedOnSize)
        #endif
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            options
            if let notice = status.notice {
                NoticeBanner(message: notice)
            } else if status == .cancelled {
                Label("Cancelled. Nothing was deleted.", systemImage: "xmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            footer
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: headerSymbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isConfirming ? AnyShapeStyle(.ember) : AnyShapeStyle(.secondary))
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                .symbolEffect(.pulse, isActive: isConfirming && !reduceMotion)
                // The value holds still under Reduce Motion, so the wiggle never fires.
                .symbolEffect(.wiggle, value: reduceMotion ? false : isDeleting)
                .frame(width: iconWell, height: iconWell)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Delete \(name)?")
                    .font(.headline)
                    .lineLimit(2)
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 0) {
            option("Delete configurations", systemImage: "doc.badge.gearshape", isOn: $configurations)
            Divider().padding(.leading, optionIndent)
            option("Delete volumes", systemImage: "externaldrive", isOn: $volumes)
            if volumes {
                Label("The data in those volumes goes away.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.glow)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, optionIndent)
                    .padding(.trailing, 12)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Divider().padding(.leading, optionIndent)
            option("Docker cleanup", systemImage: "eraser", isOn: $dockerCleanup)
            Divider().padding(.leading, optionIndent)
            option("Delete connected networks", systemImage: "network", isOn: $connectedNetworks)
        }
        .well(cornerRadius: 12)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.glow.opacity(volumes ? 0.45 : 0), lineWidth: 1)
        }
        .disabled(status.isBusy)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(footnote, systemImage: method == .unavailable ? "lock.slash" : method.systemImage)
                .font(.footnote)
                .foregroundStyle(method == .unavailable ? AnyShapeStyle(.glow) : AnyShapeStyle(.secondary))
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            HStack(spacing: 10) {
                #if os(macOS)
                Spacer()
                #endif
                // Cancel stays open while the owner is asked, and withdraws the delete. Once sent, it can't be.
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isDeleting)
                    .accessibilityHint(isConfirming ? "Withdraws the delete" : "Closes without deleting")
                    .modifier(FooterButton(prominent: false))
                Button(role: .destructive, action: confirm) {
                    ZStack {
                        // Hidden while busy, so the button keeps its width while the spinner shows.
                        Text("Delete")
                            .opacity(status.isBusy ? 0 : 1)
                        if status.isBusy {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(!canDelete)
                // ⌘⌫ deletes, as in the Finder. Return must not, so a stray key never confirms a delete.
                .keyboardShortcut(.delete, modifiers: .command)
                .accessibilityLabel("Delete")
                .accessibilityHint("Asks for \(method.promptName), then deletes \(name)")
                .modifier(FooterButton(prominent: true))
            }
        }
    }

    private var optionIndent: CGFloat { 12 + glyphWidth + 10 }

    private func option(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: glyphWidth)
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

/// The Mac keeps the popover's standard buttons. An iPhone sheet fills its width with two large ones, and the
/// destructive one stands out, as a system confirmation's does.
private struct FooterButton: ViewModifier {
    var prominent: Bool

    func body(content: Content) -> some View {
        #if os(macOS)
        content
        #else
        content
            .frame(maxWidth: .infinity)
            .controlSize(.large)
            .glassButton(prominent: prominent)
        #endif
    }
}

#Preview("Delete a resource") {
    ResourceRemovalDialog(
        name: "marketing-site", status: .ready, method: .touchID, onDelete: { _ in }, onCancel: {})
}

#Preview("Waiting for Face ID") {
    ResourceRemovalDialog(
        name: "marketing-site", status: .confirming, method: .faceID, onDelete: { _ in }, onCancel: {})
}

#Preview("Deleting") {
    ResourceRemovalDialog(
        name: "marketing-site", status: .deleting, method: .touchID, onDelete: { _ in }, onCancel: {})
}

#Preview("Cancelled") {
    ResourceRemovalDialog(
        name: "marketing-site", status: .cancelled, method: .touchID, onDelete: { _ in }, onCancel: {})
}

#Preview("Coolify refused") {
    ResourceRemovalDialog(
        name: "marketing-site",
        status: .problem("The environment still has resources."),
        method: .touchID,
        onDelete: { _ in },
        onCancel: {}
    )
}

#Preview("No passcode set") {
    ResourceRemovalDialog(
        name: "marketing-site", status: .ready, method: .unavailable, onDelete: { _ in }, onCancel: {})
}

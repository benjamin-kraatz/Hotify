import CoolifyAPI
import SwiftUI

/// A service's compose file in its Settings: what it runs, and the way into the editor. The text itself stays in
/// the editor, behind the variable lock, since a compose file can hold passwords.
struct ComposeSection: View {
    /// `nil` when Coolify kept the file from this token.
    var compose: String?
    /// Whether the draft's file differs from the saved one.
    var isChanged: Bool
    /// Opens the editor. `nil` leaves the button out, as in a preview of a single tab.
    var onEdit: (() -> Void)?

    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Section {
            if let compose {
                let outline = ComposeOutline(compose)
                HStack(spacing: 12) {
                    ComposeMark(size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary(outline))
                            .fontWeight(.medium)
                        if outline.containers.isEmpty {
                            Text("Hotify reads no containers in it")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(outline.containers.map(\.name).joined(separator: ", "))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    Spacer(minLength: 8)
                    if isChanged {
                        Text("Edited")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.ember)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ember.opacity(0.12), in: .capsule)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .animation(reduceMotion ? nil : .snappy, value: isChanged)
                .accessibilityElement(children: .combine)
                .accessibilityValue(isChanged ? "Edited, not saved" : "")
                if let onEdit {
                    Button(action: onEdit) {
                        Label("Edit Compose File", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .help("Open the compose file in the editor (⇧⌘E)")
                    .accessibilityHint("Opens the compose file on its own screen")
                }
            } else {
                Text(
                    "Coolify didn't send the compose file. Reading it takes a token with the root or read:sensitive permission, made by a team admin under Keys & Tokens."
                )
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Compose File")
        } footer: {
            if compose != nil {
                Text(
                    "Coolify keeps the passwords it made and the containers the file still names. Saving doesn't restart the service."
                )
            }
        }
    }

    /// How many containers the file names, and how long it is, like `2 containers · 14 lines`.
    private func summary(_ outline: ComposeOutline) -> String {
        let containers =
            switch outline.containers.count {
            case 0: "Docker Compose"
            case 1: "1 container"
            default: "\(outline.containers.count) containers"
            }
        return "\(containers) · \(lineCount == 1 ? "1 line" : "\(lineCount) lines")"
    }

    private var lineCount: Int {
        guard let compose, !compose.isEmpty else { return 0 }
        return compose.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
    }
}

#Preview {
    Form {
        ComposeSection(
            compose: "services:\n  web:\n    image: nginx\n  cache:\n    image: redis:7\n", isChanged: true, onEdit: {})
        ComposeSection(compose: nil, isChanged: false, onEdit: nil)
    }
    .formStyle(.grouped)
    .frame(width: 520, height: 420)
}

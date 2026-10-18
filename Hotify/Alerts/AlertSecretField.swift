import SwiftUI

/// A credential or webhook address in an alert channel's form.
///
/// The field starts blank, and blank keeps what Coolify has. A value Coolify shared shows only after the variable
/// lock opens. Remove clears the stored value on save, and Undo takes that back.
struct AlertSecretField: View {
    var title: String
    var example: String
    /// The stored value, when Coolify shared it.
    var stored: String?
    /// Coolify kept the value back from this token, so it may or may not be set.
    var isWithheld: Bool
    @Binding var text: String
    @Binding var isRemoved: Bool
    var problem: String?

    /// Missing in previews, which show stored values as they are.
    @SwiftUI.Environment(VariableLock.self) private var lock: VariableLock?
    @State private var isRevealed = false

    private var isOpen: Bool { lock?.isOpen ?? true }

    private var prompt: String {
        if stored != nil { return "Saved in Coolify. Type to replace it." }
        if isWithheld { return "Kept by Coolify. Type to replace it." }
        return example
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isRemoved {
                LabeledContent(title) {
                    HStack(spacing: 8) {
                        Text("Removed when you save")
                            .foregroundStyle(.secondary)
                        Button("Undo") { isRemoved = false }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    SecureField(title, text: $text, prompt: Text(prompt))
                        .autocorrectionDisabled()
                        #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .textContentType(.none)
                        #endif
                    if stored != nil {
                        Button(
                            isRevealed && isOpen ? "Hide saved value" : "Show saved value",
                            systemImage: isRevealed && isOpen ? "eye.slash" : "eye"
                        ) {
                            Task { await toggleReveal() }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help(isRevealed && isOpen ? "Hide the saved value" : "Show the saved value")
                    }
                    if stored != nil || isWithheld {
                        Button("Remove \(title)", systemImage: "trash") {
                            text = ""
                            isRevealed = false
                            isRemoved = true
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Remove the saved value when you save")
                    }
                }
                if let stored, isRevealed, isOpen {
                    Text(verbatim: stored)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .accessibilityLabel("Saved \(title)")
                        .accessibilityValue(stored)
                }
            }
            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.glow)
            }
        }
        .onChange(of: isOpen) { _, isOpen in
            if !isOpen { isRevealed = false }
        }
        .animation(.snappy, value: isRevealed && isOpen)
        .animation(.snappy, value: isRemoved)
    }

    private func toggleReveal() async {
        if isRevealed && isOpen {
            isRevealed = false
            return
        }
        if let lock, !lock.isOpen {
            guard await lock.unlock() else { return }
        }
        isRevealed = true
    }
}

#Preview("Saved") {
    @Previewable @State var text = ""
    @Previewable @State var removed = false
    Form {
        AlertSecretField(
            title: "Webhook URL",
            example: "https://discord.com/api/webhooks/…",
            stored: "https://discord.com/api/webhooks/1/preview",
            isWithheld: false,
            text: $text,
            isRemoved: $removed
        )
        AlertSecretField(
            title: "Bot token",
            example: "123456:ABC-DEF…",
            stored: nil,
            isWithheld: true,
            text: .constant(""),
            isRemoved: .constant(false)
        )
        AlertSecretField(
            title: "API token",
            example: "The application's token",
            stored: nil,
            isWithheld: false,
            text: .constant("x"),
            isRemoved: .constant(false),
            problem: "Required while Pushover is on."
        )
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 320)
}

import SwiftUI

/// The foot of every screen that creates a resource: where it lands, and the button that creates it.
///
/// The status sits beside the button where both fit, and above it in a narrow column such as the inspector or an
/// iPhone. In the inspector the bar also holds Cancel, since the Mac sheet has no toolbar row to spare for it.
struct CreateBar: View {
    var isCreating: Bool
    var status: String
    /// The status reports a problem, which glows amber.
    var isProblem = false
    var summary: String
    var buttonTitle: String
    var canCreate: Bool
    var help: String?
    var action: () -> Void

    @SwiftUI.Environment(\.provisioningCancel) private var cancel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                statusLine
                Spacer(minLength: 0)
                buttons
            }
            VStack(alignment: .leading, spacing: 12) {
                statusLine
                buttons
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
        .animation(.snappy, value: isCreating)
    }

    private var statusLine: some View {
        HStack(spacing: 14) {
            FlameGlyph(heat: isCreating ? .warming : .cold, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(status)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isProblem ? AnyShapeStyle(.glow) : AnyShapeStyle(.primary))
                    .contentTransition(.interpolate)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            if let cancel {
                Button("Cancel") { cancel() }
                    .glassButton()
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
            }
            Button(action: action) {
                Text(buttonTitle)
                    .opacity(isCreating ? 0 : 1)
                    .overlay {
                        if isCreating {
                            ProgressView().controlSize(.small)
                        }
                    }
            }
            .glassButton(prominent: true)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!canCreate)
            .help(help ?? buttonTitle)
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        Spacer()
        CreateBar(
            isCreating: false, status: "Ready to create", summary: "On localhost, in Website · production.",
            buttonTitle: "Create Service", canCreate: true
        ) {}
        CreateBar(
            isCreating: true, status: "Creating n8n…", summary: "On localhost, in Website · production.",
            buttonTitle: "Create Service", canCreate: true
        ) {}
        .environment(\.provisioningCancel, ProvisioningCancel {})
        .frame(width: 380)
    }
    .frame(width: 720, height: 300)
}

import SwiftUI

/// The one Save for a resource's settings, wherever they are edited: what holds it back, Revert, and Save.
struct ConfigurationSaveBar: View {
    var model: ConfigurationModel

    var body: some View {
        let problem = model.draft?.problem
        HStack(spacing: 12) {
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.glow)
                    .lineLimit(3)
            } else {
                Text("Unsaved changes")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Revert") {
                model.revert()
            }
            .glassButton()
            .disabled(model.isSaving)
            Button {
                Task { await model.save() }
            } label: {
                if model.isSaving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Save")
                }
            }
            .glassButton(prominent: true)
            .disabled(problem != nil || model.isSaving || model.hasComposeConflict)
            .keyboardShortcut("s", modifiers: .command)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}

#Preview {
    ConfigurationSaveBar(
        model: ConfigurationModel(saved: ResourceConfiguration(kind: .service, name: "edge", description: ""))
    )
    .frame(width: 520)
    .padding(.vertical)
}

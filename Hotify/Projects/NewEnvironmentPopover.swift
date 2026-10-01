import SwiftUI

/// Names a new environment, in a popover at the button that asked for it. Coolify takes only a name when it
/// creates one, so there is nothing else to fill in. An iPhone has no room for a popover and shows this as a
/// short sheet.
struct NewEnvironmentPopover: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss

    var projectName: String
    /// Names the project already uses, to catch a duplicate before Coolify answers 409.
    var takenNames: Set<String> = []
    var onAdd: (_ name: String) async throws -> Void

    @State private var name = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @FocusState private var isFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nameProblem: String? {
        guard !trimmedName.isEmpty else { return nil }
        // Coolify's own rule for names. Catching it here saves a round trip.
        if trimmedName.count < 3 {
            return "A name needs at least 3 characters."
        }
        if takenNames.contains(trimmedName) {
            return "\(trimmedName) already exists."
        }
        return nil
    }

    private var canAdd: Bool {
        !trimmedName.isEmpty && nameProblem == nil && !isSaving
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Environment")
                .font(.headline)

            TextField("Name", text: $name, prompt: Text(verbatim: "staging"))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                #if os(iOS)
            .textInputAutocapitalization(.never)
                #endif
                .focused($isFocused)
                .onSubmit {
                    if canAdd {
                        Task { await add() }
                    }
                }

            if let problem = nameProblem ?? saveError {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.glow)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            } else {
                Text("It starts empty in \(projectName). Resources are created in it from Coolify.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    Task { await add() }
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Add")
                    }
                }
                .glassButton(prominent: true)
                .disabled(!canAdd)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 420, alignment: .leading)
        .presentationDetents([.height(230)])
        .onChange(of: name) { _, _ in saveError = nil }
        .onAppear {
            isFocused = true
        }
        .animation(.snappy, value: nameProblem)
        .animation(.snappy, value: saveError)
    }

    private func add() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await onAdd(trimmedName)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

#Preview {
    NewEnvironmentPopover(projectName: "Website", takenNames: ["production"], onAdd: { _ in })
}

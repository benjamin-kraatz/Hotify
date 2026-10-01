import SwiftUI

/// Names a new project or environment and picks its color, in a popover at the button that asked for it. Coolify
/// takes only a name when it creates one. The color stays with Hotify. An iPhone has no room for a popover and
/// shows this as a short sheet.
struct NewPlacePopover: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss

    var kind: PlaceKind
    /// Says what happens to the new project or environment. Each kind has its own when this is `nil`.
    var note: String?
    /// Names already in use beside the new one, to catch a duplicate before Coolify answers 409.
    var takenNames: Set<String> = []
    var onAdd: (_ name: String, _ tint: PlaceTint?) async throws -> Void

    @State private var name = ""
    @State private var tint: PlaceTint?
    @State private var isSaving = false
    @State private var saveError: String?
    @FocusState private var isFocused: Bool

    private var title: String {
        kind == .project ? "New Project" : "New Environment"
    }

    private var namePrompt: String {
        kind == .project ? "Website" : "staging"
    }

    private var defaultNote: String {
        kind == .project
            ? "Coolify gives a new project a production environment to start with."
            : "It starts empty. Resources are created in it from Coolify."
    }

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
            Text(title)
                .font(.headline)

            TextField("Name", text: $name, prompt: Text(verbatim: namePrompt))
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

            PlaceTintPicker(selection: $tint)

            if let problem = nameProblem ?? saveError {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.glow)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            } else {
                Text(note ?? defaultNote)
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
        .presentationDetents([.height(320)])
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
            try await onAdd(trimmedName, tint)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

#Preview("Environment") {
    NewPlacePopover(
        kind: .environment,
        note: "It starts empty in Website. Resources are created in it from Coolify.",
        takenNames: ["production"],
        onAdd: { _, _ in }
    )
}

#Preview("Project") {
    NewPlacePopover(kind: .project, onAdd: { _, _ in })
}

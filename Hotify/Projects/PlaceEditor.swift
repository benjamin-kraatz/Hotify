import CoolifyAPI
import SwiftUI

/// Renames a project or an environment, and says what it is for.
struct PlaceEditor: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss

    var title: String
    var namePrompt = "Name"
    /// Names in use beside this one, to catch a duplicate before Coolify answers 409.
    var takenNames: Set<String> = []
    var onSave: (_ name: String, _ description: String) async throws -> Void

    @State private var name: String
    @State private var description: String
    @State private var isSaving = false
    @State private var saveError: String?
    @FocusState private var focus: Field?

    private let originalName: String
    private let originalDescription: String

    private enum Field: Hashable {
        case name
        case description
    }

    init(
        title: String,
        namePrompt: String = "Name",
        name: String = "",
        description: String = "",
        takenNames: Set<String> = [],
        onSave: @escaping (_ name: String, _ description: String) async throws -> Void
    ) {
        self.title = title
        self.namePrompt = namePrompt
        self.takenNames = takenNames
        self.onSave = onSave
        originalName = name
        originalDescription = description
        _name = State(initialValue: name)
        _description = State(initialValue: description)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nameProblem: String? {
        guard !trimmedName.isEmpty, trimmedName != originalName else { return nil }
        // Coolify's own rule for names. Catching it here saves a round trip.
        if trimmedName.count < 3 {
            return "A name needs at least 3 characters."
        }
        if takenNames.contains(trimmedName) {
            return "\(trimmedName) already exists."
        }
        return nil
    }

    private var isDirty: Bool {
        trimmedName != originalName || trimmedDescription != originalDescription
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && nameProblem == nil && isDirty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text(namePrompt))
                        .autocorrectionDisabled()
                        .focused($focus, equals: .name)
                        .onSubmit {
                            focus = .description
                        }
                    TextField(
                        "Description", text: $description, prompt: Text("What it is for"), axis: .vertical
                    )
                    .lineLimit(1...4)
                    .focused($focus, equals: .description)
                } footer: {
                    if let nameProblem {
                        Label(nameProblem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.glow)
                    }
                }

                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.glow)
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                        .disabled(!canSave)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .onChange(of: name) { _, _ in saveError = nil }
            .onChange(of: description) { _, _ in saveError = nil }
            .onAppear {
                focus = .name
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 260)
        #endif
        .interactiveDismissDisabled(isSaving || isDirty)
        .animation(.snappy, value: nameProblem)
        .animation(.snappy, value: saveError)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(trimmedName, trimmedDescription)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

/// A rename or a new environment that Coolify refused, worded for the form that asked.
struct PlaceWriteError: Error, LocalizedError {
    var message: String
    var errorDescription: String? { message }

    init(message: String) {
        self.message = message
    }

    /// Coolify answers a rejected name with "Validation failed." and the reason under `errors`, so this takes both.
    init(_ error: Error) {
        message = (error as? CoolifyError)?.summary ?? error.localizedDescription
    }
}

#Preview("Edit project") {
    PlaceEditor(
        title: "Edit Project",
        name: "Website",
        description: "The marketing site, its API, and what they store.",
        onSave: { _, _ in }
    )
}

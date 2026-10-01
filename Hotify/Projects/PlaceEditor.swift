import CoolifyAPI
import SwiftUI

/// Names a project or an environment, and says what it is for.
struct PlaceEditor: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss

    var title: String
    var confirmTitle = "Save"
    var namePrompt = "Name"
    /// Coolify takes only a name when it creates an environment, so the description waits for an edit.
    var hasDescription = true
    /// Names in use beside this one, to catch a duplicate before Coolify answers 409.
    var takenNames: Set<String> = []
    var note: String?
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
        confirmTitle: String = "Save",
        namePrompt: String = "Name",
        name: String = "",
        description: String = "",
        hasDescription: Bool = true,
        takenNames: Set<String> = [],
        note: String? = nil,
        onSave: @escaping (_ name: String, _ description: String) async throws -> Void
    ) {
        self.title = title
        self.confirmTitle = confirmTitle
        self.namePrompt = namePrompt
        self.hasDescription = hasDescription
        self.takenNames = takenNames
        self.note = note
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
                            if hasDescription {
                                focus = .description
                            } else if canSave {
                                Task { await save() }
                            }
                        }
                    if hasDescription {
                        TextField(
                            "Description", text: $description, prompt: Text("What it is for"), axis: .vertical
                        )
                        .lineLimit(1...4)
                        .focused($focus, equals: .description)
                    }
                } footer: {
                    if let nameProblem {
                        Label(nameProblem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.glow)
                    } else if let note {
                        Text(note)
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
                        Button(confirmTitle) {
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
        .frame(minWidth: 420, idealWidth: 460, minHeight: hasDescription ? 260 : 200)
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

/// A rename or a new environment that Coolify refused, worded for the editor.
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

#Preview("New environment") {
    PlaceEditor(
        title: "New Environment",
        confirmTitle: "Add",
        namePrompt: "staging",
        hasDescription: false,
        takenNames: ["production"],
        note: "It starts empty. Create resources in it from Coolify.",
        onSave: { _, _ in }
    )
}

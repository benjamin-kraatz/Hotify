import CoolifyAPI
import SwiftUI

/// Adds a variable, or changes the value and options of one. Coolify cannot rename a key, so an existing key is fixed.
struct VariableEditor: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss

    /// `nil` to add a new variable.
    var original: VariableLine?
    /// Applications keep a second set of variables for previews. Nothing else does.
    var hasPreviewVariables: Bool
    /// Keys already in use, to catch a duplicate before Coolify answers 409. Split by preview for applications.
    var takenKeys: (_ isPreview: Bool) -> Set<String>
    var onSave: (EnvironmentVariableDraft) async throws -> Void
    var onDelete: (() -> Void)?

    @State private var key: String
    @State private var value: String
    @State private var isPreview: Bool
    @State private var isLiteral: Bool
    @State private var isMultiline: Bool
    @State private var isShownOnce: Bool
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var isConfirmingDelete = false
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case key
        case value
    }

    init(
        original: VariableLine?,
        hasPreviewVariables: Bool,
        takenKeys: @escaping (_ isPreview: Bool) -> Set<String> = { _ in [] },
        onSave: @escaping (EnvironmentVariableDraft) async throws -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.original = original
        self.hasPreviewVariables = hasPreviewVariables
        self.takenKeys = takenKeys
        self.onSave = onSave
        self.onDelete = onDelete
        _key = State(initialValue: original?.key ?? "")
        _value = State(initialValue: original?.value ?? "")
        _isPreview = State(initialValue: original?.isPreview ?? false)
        _isLiteral = State(initialValue: original?.isLiteral ?? false)
        _isMultiline = State(initialValue: original?.isMultiline ?? false)
        _isShownOnce = State(initialValue: original?.isShownOnce ?? false)
    }

    private var isNew: Bool { original == nil }
    /// Coolify withheld the value, so saving must send a new one or it would overwrite the old one with nothing.
    private var isValueUnknown: Bool { original != nil && original?.value == nil }

    /// Coolify turns spaces into underscores on its side. Doing it here shows the key it will store.
    private var normalizedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "_")
    }

    private var keyProblem: String? {
        guard isNew, !normalizedKey.isEmpty else { return nil }
        if normalizedKey.contains("=") {
            return "A key cannot contain “=”."
        }
        if normalizedKey.first?.isNumber == true {
            return "A key cannot start with a digit."
        }
        if takenKeys(isPreview).contains(normalizedKey) {
            return "\(normalizedKey) already exists. Edit that one instead."
        }
        return nil
    }

    private var isDirty: Bool {
        guard let original else { return true }
        return value != (original.value ?? "") || isLiteral != original.isLiteral
            || isMultiline != original.isMultiline || isShownOnce != original.isShownOnce
    }

    /// Whether a swipe down would throw away typing.
    private var hasEdits: Bool {
        isNew ? !(key.isEmpty && value.isEmpty) : isDirty
    }

    private var canSave: Bool {
        !normalizedKey.isEmpty && keyProblem == nil && isDirty && !isSaving && !(isValueUnknown && value.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isNew {
                        TextField("Key", text: $key, prompt: Text(verbatim: "API_URL"))
                            .font(.body.monospaced())
                            .autocorrectionDisabled()
                            .focused($focus, equals: .key)
                            .onSubmit { focus = .value }
                            #if os(iOS)
                        .textInputAutocapitalization(.characters)
                            #endif
                    } else {
                        LabeledContent("Key") {
                            Text(normalizedKey)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                        }
                    }

                    TextField(
                        "Value",
                        text: $value,
                        prompt: Text(isValueUnknown ? "Type a new value" : "Value"),
                        axis: .vertical
                    )
                    .font(.body.monospaced())
                    .lineLimit(isMultiline ? 4...12 : 1...6)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .value)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                } header: {
                    Text("Variable")
                } footer: {
                    if let keyProblem {
                        Label(keyProblem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.glow)
                    } else if isValueUnknown {
                        Text("Coolify does not send this value back. Saving replaces it with what you type here.")
                    } else if isNew, normalizedKey != key.trimmingCharacters(in: .whitespacesAndNewlines) {
                        Text("Saved as \(normalizedKey).")
                    }
                }

                Section("Options") {
                    if hasPreviewVariables, isNew {
                        Toggle(isOn: $isPreview) {
                            Text("For preview deployments")
                            Text("Pull request previews read their own set of variables.")
                        }
                    }
                    Toggle(isOn: $isMultiline) {
                        Text("Multiline")
                        Text("Keep line breaks, as in a certificate or a key file.")
                    }
                    Toggle(isOn: $isLiteral) {
                        Text("Literal")
                        Text("Pass the value as written, without expanding $ references.")
                    }
                    Toggle(isOn: $isShownOnce) {
                        Text("Hide after saving")
                        Text(
                            "Coolify stops showing the value, here and in its own dashboard. You can still replace it.")
                    }
                }

                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.glow)
                            .textSelection(.enabled)
                    }
                }

                if onDelete != nil {
                    Section {
                        Button("Delete Variable", role: .destructive) {
                            isConfirmingDelete = true
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "New Variable" : "Edit Variable")
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
                        Button(isNew ? "Add" : "Save") {
                            Task { await save() }
                        }
                        .disabled(!canSave)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .confirmationDialog(
                "Delete \(normalizedKey)?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
            } message: {
                Text("Coolify removes it for good. Running containers keep the old value until they restart.")
            }
            .onChange(of: key) { _, _ in saveError = nil }
            .onChange(of: value) { _, _ in saveError = nil }
            .onAppear {
                focus = isNew ? .key : .value
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 440)
        #endif
        .interactiveDismissDisabled(isSaving || hasEdits)
        .animation(.snappy, value: keyProblem)
        .animation(.snappy, value: saveError)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let draft = EnvironmentVariableDraft(
            key: normalizedKey,
            value: value,
            isPreview: hasPreviewVariables ? isPreview : nil,
            isLiteral: isLiteral,
            isMultiline: isMultiline,
            isShownOnce: isShownOnce
        )
        do {
            try await onSave(draft)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

#Preview("New") {
    VariableEditor(original: nil, hasPreviewVariables: true, takenKeys: { _ in ["API_URL"] }, onSave: { _ in })
}

#Preview("Edit") {
    VariableEditor(
        original: VariableLine(id: "1", key: "DATABASE_URL", value: "postgres://app:secret@db:5432/app"),
        hasPreviewVariables: false,
        onSave: { _ in },
        onDelete: {}
    )
}

#Preview("Hidden value") {
    VariableEditor(
        original: VariableLine(id: "3", key: "STRIPE_SECRET_KEY", isShownOnce: true),
        hasPreviewVariables: false,
        onSave: { _ in },
        onDelete: {}
    )
}

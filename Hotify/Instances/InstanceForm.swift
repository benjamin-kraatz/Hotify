import SwiftUI

/// Adds a Coolify instance, or edits one that is already saved.
struct InstanceForm: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss

    var title: String
    var confirmTitle: String
    var overrideError: String?
    var onSave: (String, String, String) throws -> Void

    @State private var name: String
    @State private var baseURL: String
    @State private var token: String
    @State private var isTokenVisible = false
    @State private var errorMessage: String?

    private let originalName: String
    private let originalURL: String
    private let originalToken: String

    init(
        title: String = "Add Instance",
        confirmTitle: String = "Add",
        name: String = "",
        baseURL: String = "",
        token: String = "",
        overrideError: String? = nil,
        onSave: @escaping (String, String, String) throws -> Void
    ) {
        self.title = title
        self.confirmTitle = confirmTitle
        self.overrideError = overrideError
        self.onSave = onSave
        self.originalName = name
        self.originalURL = baseURL
        self.originalToken = token
        _name = State(initialValue: name)
        _baseURL = State(initialValue: baseURL)
        _token = State(initialValue: token)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)

                    TextField("URL", text: $baseURL)
                        .textContentType(.URL)
                        #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                } header: {
                    Text("Basic information")
                }

                Section {
                    HStack {
                        if isTokenVisible {
                            TextField("API token", text: $token)
                                .textContentType(.password)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("API token", text: $token)
                                .textContentType(.password)
                                .autocorrectionDisabled()
                        }
                    }

                    HStack {
                        PasteButton(payloadType: String.self) { strings in
                            if let pastedToken = strings.first {
                                token = pastedToken
                            }
                        }
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity)

                        eyeButton
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)

                } header: {
                    Text("Authentication")
                } footer: {
                    Text(
                        "Your tokens are stored securely on the device in the Keychain and never shared with anyone else."
                    )
                }

                Section {
                    HStack {
                        TryConnectionButton()
                            .disabled(!isFormComplete)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section {
                    // Form fields
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        if let message = overrideError ?? errorMessage {
                            Text(message)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
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
                    Button(confirmTitle) {
                        submit()
                    }
                    .disabled(!isFormComplete || !isDirty)
                }
            }
        }
        #if os(macOS)
        .padding()
        #endif
        .frame(minWidth: 360)
        .interactiveDismissDisabled(isDirty)
    }

    private var isFormComplete: Bool {
        !(name.isEmpty || baseURL.isEmpty || token.isEmpty)
    }

    private var isDirty: Bool {
        name != originalName || baseURL != originalURL || token != originalToken
    }

    private var eyeButton: some View {
        Button {
            isTokenVisible.toggle()
        } label: {
            HStack {
                Image(systemName: isTokenVisible ? "eye" : "eye.slash")
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace))
                Text(isTokenVisible ? "Hide" : "Show")
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isTokenVisible ? "Hide API token" : "Show API token")
    }

    private func submit() {
        do {
            try onSave(name, baseURL, token)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    InstanceForm { _, _, _ in }
}

#Preview("Edit") {
    InstanceForm(
        title: "Edit Instance",
        confirmTitle: "Save",
        name: "Home",
        baseURL: "https://coolify.example",
        token: "secret"
    ) { _, _, _ in }
}

#Preview("With error") {
    InstanceForm(
        overrideError:
            "The connection could not be established. Please provide us your credit card info and we will charge you."
    ) { _, _, _ in }
}

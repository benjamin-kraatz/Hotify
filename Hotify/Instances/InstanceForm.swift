import CoolifyAPI
import SwiftUI

/// Adds a Coolify instance, or edits one that is already saved.
struct InstanceForm: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss

    var title: String
    var confirmTitle: String
    var overrideError: String?
    var overrideSuccess: String?
    var onSave: (String, String, String) throws -> Void

    @State private var name: String
    @State private var baseURL: String
    @State private var token: String
    @State private var isTokenVisible = false
    @State private var saveError: String?
    @State private var connectionError: String?
    @State private var connectionSuccess: String?
    @State private var connectionGeneration = 0

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
        overrideSuccess: String? = nil,
        onSave: @escaping (String, String, String) throws -> Void
    ) {
        self.title = title
        self.confirmTitle = confirmTitle
        self.overrideError = overrideError
        self.overrideSuccess = overrideSuccess
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
                        TryConnectionButton(resetID: connectionGeneration) {
                            await tryConnection()
                        }
                        .disabled(!canTryConnection)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } footer: {
                    connectionStatus
                        .animation(.easeInOut(duration: 0.2), value: connectionError)
                        .animation(.easeInOut(duration: 0.2), value: connectionSuccess)
                        .animation(.easeInOut(duration: 0.2), value: saveError)
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
            .onChange(of: name) { _, _ in
                saveError = nil
            }
            .onChange(of: baseURL) { _, _ in
                connectionGeneration += 1
                clearConnectionFeedback()
            }
            .onChange(of: token) { _, _ in
                connectionGeneration += 1
                clearConnectionFeedback()
            }
        }
        #if os(macOS)
        .padding()
        #endif
        .frame(minWidth: 360)
        .interactiveDismissDisabled(isDirty)
    }

    @ViewBuilder
    private var connectionStatus: some View {
        if let message = overrideError ?? connectionError ?? saveError {
            Text(message)
                .foregroundStyle(.red)
        } else if let message = overrideSuccess ?? connectionSuccess {
            Text(message)
                .foregroundStyle(.green)
        }
    }

    private var canTryConnection: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        connectionError = nil
        connectionSuccess = nil
        do {
            try onSave(name, baseURL, token)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func clearConnectionFeedback() {
        connectionError = nil
        connectionSuccess = nil
        saveError = nil
    }

    private func tryConnection() async {
        let url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let generation = connectionGeneration
        clearConnectionFeedback()

        do {
            // A fast answer finishes before the spinner is visible.
            try await Task.sleep(for: .milliseconds(100))
            let client = try CoolifyClient(instanceURL: url, token: apiToken)
            let probe = try await probe(client)
            guard stillCurrent(url: url, token: apiToken, generation: generation) else { return }
            let message = connectionSummary(team: probe.team, version: probe.version)
            connectionSuccess = message
            announce(message)
        } catch is CancellationError {
            return
        } catch {
            guard stillCurrent(url: url, token: apiToken, generation: generation) else { return }
            let message = (error as? CoolifyError)?.message ?? error.localizedDescription
            connectionError = message
            announce(message)
        }
    }

    private func probe(_ client: CoolifyClient) async throws -> (team: String, version: String) {
        async let versionTask = client.version()
        async let teamTask = client.currentTeam()
        do {
            // Health answers without a token, so the team request is what proves this token works.
            let team = try await teamTask
            let version = (try? await versionTask) ?? ""
            return (team.name, version)
        } catch {
            _ = try? await versionTask
            throw error
        }
    }

    private func stillCurrent(url: String, token apiToken: String, generation: Int) -> Bool {
        generation == connectionGeneration
            && baseURL.trimmingCharacters(in: .whitespacesAndNewlines) == url
            && token.trimmingCharacters(in: .whitespacesAndNewlines) == apiToken
    }

    private func connectionSummary(team: String, version: String) -> String {
        let trimmedTeam = team.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTeam.isEmpty, !trimmedVersion.isEmpty {
            return "Connected to \(trimmedTeam). Coolify \(trimmedVersion)."
        }
        if !trimmedTeam.isEmpty {
            return "Connected to \(trimmedTeam)."
        }
        if !trimmedVersion.isEmpty {
            return "Connected. Coolify \(trimmedVersion)."
        }
        return "Connected."
    }

    private func announce(_ message: String) {
        guard !message.isEmpty else { return }
        AccessibilityNotification.Announcement(message).post()
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

#Preview("Connected") {
    InstanceForm(
        overrideSuccess: "Connected to Home. Coolify 4.0.0-beta.436."
    ) { _, _, _ in }
}

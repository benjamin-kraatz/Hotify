import SwiftUI

/// Stores optional GitHub read access for the PR picker in the Keychain.
struct GitHubAccessSheet: View {
    var onChanged: () -> Void
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var error: String?
    @State private var hasToken = GitHubCredentialStore.load() != nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("GitHub token", text: $token)
                        #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                        #endif
                } footer: {
                    Text(
                        "For private repositories, use a fine-grained token with read access to Pull requests for the repositories you want to load. Hotify stores it in Keychain and sends it only to GitHub. Public repositories work without a token."
                    )
                }
                if hasToken {
                    Section {
                        Button("Disconnect GitHub") {
                            GitHubCredentialStore.delete()
                            onChanged()
                            dismiss()
                        }
                    } footer: {
                        Text("A GitHub token is connected. Save a new token to replace it.")
                    }
                }
                if let error { Section { NoticeBanner(message: error) } }
            }
            .formStyle(.grouped)
            .navigationTitle("GitHub access")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try GitHubCredentialStore.save(token.trimmingCharacters(in: .whitespacesAndNewlines))
                            token = ""
                            onChanged()
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(width: 480, height: 340)
        #endif
    }
}

#Preview { GitHubAccessSheet(onChanged: {}) }

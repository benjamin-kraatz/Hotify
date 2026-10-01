import CoolifyAPI
import SwiftUI

/// Stores optional GitHub read access for the PR picker in the Keychain.
///
/// It walks through making a token with a link that fills in GitHub's form, then checks the pasted token against the
/// application's repository before saving it.
struct GitHubAccessSheet: View {
    /// The repository to check a new token against. `nil` saves without a check.
    var repository: GitHubRepository?
    var onChanged: () -> Void

    @SwiftUI.Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var error: String?
    @State private var isChecking = false
    /// Set once a check fails, so the user can keep a token meant for other repositories.
    @State private var canSaveAnyway = false
    @State private var hasToken = GitHubCredentialStore.load() != nil

    private var trimmed: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var looksWrong: Bool {
        !trimmed.isEmpty && !GitHubTokenTemplate.looksLikeToken(trimmed)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    intro
                }

                Section {
                    Link(destination: GitHubTokenTemplate.url()) {
                        Label("Create Token on GitHub", systemImage: "arrow.up.right.square")
                    }
                    .fontWeight(.semibold)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(
                            "GitHub opens with the token filled in: read-only access to pull requests, valid for \(GitHubTokenTemplate.expiryDays) days. Under Repository access, choose the repositories Hotify should read, then generate it."
                        )
                        Text(
                            "For an organization's repositories, choose the organization as Resource owner first. GitHub clears the permissions when the owner changes, so set Pull requests back to Read-only."
                        )
                        .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                } header: {
                    StepHeader(number: 1, title: "Create a token")
                }

                Section {
                    HStack(spacing: 10) {
                        SecureField("github_pat_…", text: $token)
                            #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                            #endif
                            .onSubmit(save)
                        PasteButton(payloadType: String.self) { strings in
                            if let pasted = strings.first {
                                token = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                        .labelStyle(.iconOnly)
                    }
                    if looksWrong {
                        Label(
                            "This doesn't look like a GitHub token. They start with github_pat_ or ghp_.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(.glow)
                        .transition(.opacity)
                    }
                } header: {
                    StepHeader(number: 2, title: "Paste it here")
                } footer: {
                    Text(pasteFootnote)
                }

                if let error {
                    Section {
                        NoticeBanner(message: error)
                        if canSaveAnyway {
                            Button("Save Anyway") { store() }
                        }
                    }
                }

                if hasToken {
                    Section {
                        HStack(spacing: 10) {
                            FlameGlyph(heat: .lit, height: 16, tone: .preview)
                            Text("A token is connected")
                            Spacer()
                            Button("Disconnect", role: .destructive) {
                                GitHubCredentialStore.delete()
                                onChanged()
                                dismiss()
                            }
                        }
                    } footer: {
                        Text("Paste a new token above to replace it.")
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(isChecking)
            .animation(.snappy, value: looksWrong)
            .animation(.snappy, value: error)
            .navigationTitle("GitHub access")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isChecking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Save", action: save)
                            .disabled(trimmed.isEmpty)
                    }
                }
            }
        }
        .tint(.pilot)
        .onChange(of: token) { _, _ in
            error = nil
            canSaveAnyway = false
        }
        #if os(macOS)
        .frame(width: 520, height: hasToken ? 620 : 540)
        #endif
    }

    private var intro: some View {
        HStack(alignment: .top, spacing: 14) {
            FlameGlyph(heat: hasToken ? .lit : .cold, height: 34, tone: .preview)
            VStack(alignment: .leading, spacing: 4) {
                Text("Read pull requests on GitHub")
                    .font(.headline)
                Text(
                    "With a token, Hotify lists a private repository's open pull requests, with their titles and branches, when you deploy a preview. Public repositories work without one."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private var pasteFootnote: String {
        let storage = "Hotify keeps it in the Keychain and sends it only to api.github.com."
        guard let repository else { return storage }
        return "Saving checks that it can read \(repository.label). \(storage)"
    }

    private func save() {
        guard !trimmed.isEmpty, !isChecking else { return }
        guard let repository else {
            store()
            return
        }
        isChecking = true
        error = nil
        let candidate = trimmed
        Task {
            defer { isChecking = false }
            do {
                _ = try await GitHubPullRequestClient().pullRequests(repository: repository, token: candidate)
                guard candidate == trimmed else { return }
                store()
            } catch {
                guard candidate == trimmed else { return }
                let reason = (error as? CoolifyError)?.message ?? error.localizedDescription
                self.error = "The token couldn't read \(repository.label). \(reason)"
                canSaveAnyway = true
            }
        }
    }

    private func store() {
        do {
            try GitHubCredentialStore.save(trimmed)
            token = ""
            onChanged()
            dismiss()
        } catch {
            self.error = error.localizedDescription
            canSaveAnyway = false
        }
    }
}

/// A step's number in a pilot-blue disc, then its title, for the two steps of connecting GitHub.
private struct StepHeader: View {
    var number: Int
    var title: String

    var body: some View {
        HStack(spacing: 8) {
            Text(number, format: .number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(.pilot, in: .circle)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number), \(title)")
    }
}

#Preview {
    GitHubAccessSheet(repository: try? GitHubRepository("hotify/website"), onChanged: {})
}

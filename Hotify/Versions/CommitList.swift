import CoolifyAPI
import SwiftUI

/// A branch's recent commits on GitHub, newest first, as a form section to pick one from. It loads when it appears,
/// since GitHub allows 60 requests an hour without a token.
struct CommitList: View {
    var repository: GitHubRepository
    var branch: String
    /// The SHA picked or typed. A row counts as picked when its SHA starts with it.
    @Binding var selection: String
    /// Images Coolify kept, so a row can say that rolling back to it skips the build.
    var keptImages: [RollbackImage] = []
    /// How many rows show. The rest stay out of a form that has other things to say.
    var limit = 30
    /// Commits to show without asking GitHub, as in a preview.
    var preloaded: [GitHubCommit]?

    @State private var commits: [GitHubCommit] = []
    @State private var error: String?
    @State private var isLoading = false

    private var shown: [GitHubCommit] { Array((preloaded ?? commits).prefix(limit)) }

    var body: some View {
        Section {
            if isLoading, shown.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if shown.isEmpty, error == nil {
                Text("GitHub lists no commits on \(branch).")
                    .foregroundStyle(.secondary)
            }
            ForEach(shown) { commit in
                row(commit)
            }
        } header: {
            Text("Recent Commits on \(branch)")
        } footer: {
            if let error {
                Text(error)
            }
        }
        .task(id: "\(repository.label)#\(branch)") { await load() }
    }

    private func row(_ commit: GitHubCommit) -> some View {
        let isPicked = Self.matches(commit.sha, selection)
        return Button {
            selection = commit.sha
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(commit.subject)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    Text(detail(for: commit))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if keptImages.contains(where: { $0.matches(commit: commit.sha) }) {
                    Chip(text: "Image kept")
                }
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .opacity(isPicked ? 1 : 0)
                    .accessibilityHidden(!isPicked)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    private func detail(for commit: GitHubCommit) -> String {
        var parts = [commit.shortSHA]
        if let author = commit.authorLogin ?? commit.authorName {
            parts.append(author)
        }
        if let date = commit.date {
            parts.append(date.formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: " · ")
    }

    /// Whether a typed SHA, 7 characters or more, picks this commit.
    static func matches(_ sha: String, _ typed: String) -> Bool {
        let typed = typed.trimmingCharacters(in: .whitespaces).lowercased()
        return typed.count >= 7 && sha.lowercased().hasPrefix(typed)
    }

    private func load() async {
        guard preloaded == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            commits = try await GitHubCommitClient().commits(
                repository: repository, branch: branch, token: GitHubCredentialStore.load())
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = (error as? CoolifyError)?.message ?? error.localizedDescription
        }
    }
}

#Preview {
    @Previewable @State var selection = "528a020"
    Form {
        CommitList(
            repository: try! GitHubRepository("coollabsio/coolify-examples"),
            branch: "main",
            selection: $selection,
            keptImages: [RollbackImage(tag: "528a020f525ac31684b4fe5b019f9f2f2154e7f3")],
            preloaded: [
                GitHubCommit(
                    sha: "0006219f4bae86f89a3efb7dabd361db8bd6174a", message: "Update index.html",
                    authorLogin: "andrasbacsai", date: .now.addingTimeInterval(-86_400)),
                GitHubCommit(
                    sha: "528a020f525ac31684b4fe5b019f9f2f2154e7f3", message: "Update index.html",
                    authorName: "Andras", date: .now.addingTimeInterval(-864_000)),
            ]
        )
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 320)
}

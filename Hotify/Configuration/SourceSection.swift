import CoolifyAPI
import SwiftUI

/// The Settings tab's Source section for an application: its repository, branch, the commit manual deploys build, and
/// whether a push deploys. For a Docker image application, the image and its tag.
struct SourceSection: View {
    @Binding var source: ApplicationSource

    var body: some View {
        Section {
            switch source.kind {
            case .git(let repository):
                LabeledContent("Repository") {
                    if let url = Self.webURL(for: repository) {
                        Link(Self.label(for: repository), destination: url)
                    } else {
                        Text(repository)
                            .textSelection(.enabled)
                    }
                }
                TextField("Branch", text: $source.branch, prompt: Text("main"))
                    .autocorrectionDisabled()
                Picker("Deploys", selection: $source.isPinned) {
                    Text(source.trimmedBranch.isEmpty ? "The latest commit" : "Latest on \(source.trimmedBranch)")
                        .tag(false)
                    Text("One commit").tag(true)
                }
                if source.isPinned {
                    TextField("Commit", text: $source.commit, prompt: Text("528a020"))
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                }
                Toggle("Deploy on push", isOn: $source.deploysOnPush)
            case .image(let name):
                LabeledContent("Image") {
                    Text(name)
                        .textSelection(.enabled)
                }
                TextField("Tag", text: $source.tag, prompt: Text("latest"))
                    .autocorrectionDisabled()
            }
        } header: {
            Text("Source")
        } footer: {
            Text(footer)
        }

        if source.isPinned, let repository = source.gitHubRepository, !source.trimmedBranch.isEmpty {
            CommitList(repository: repository, branch: source.trimmedBranch, selection: $source.commit, limit: 8)
        }
    }

    private var footer: String {
        if source.isImage {
            return "Redeploy pulls this tag."
        }
        let branch = source.trimmedBranch.isEmpty ? "the branch" : source.trimmedBranch
        if source.isPinned {
            // Coolify's push webhook deploys the pushed commit and never reads the pin.
            return source.deploysOnPush
                ? "Redeploy builds this commit. A push to \(branch) still deploys the pushed commit, so turn off deploy on push to keep this one."
                : "Redeploy builds this commit until you pick the latest again."
        }
        return source.deploysOnPush
            ? "Redeploy builds the latest commit on \(branch), and so does every push to it."
            : "Redeploy builds the latest commit on \(branch). Pushes don't deploy."
    }

    /// A browser address for the repository, when Coolify stored one, or a GitHub `owner/name`.
    static func webURL(for repository: String) -> URL? {
        if let github = try? GitHubRepository(repository) {
            return URL(string: "https://github.com/\(github.owner)/\(github.name)")
        }
        guard let url = URL(string: repository), url.scheme == "https" || url.scheme == "http", url.host() != nil
        else { return nil }
        return url
    }

    static func label(for repository: String) -> String {
        (try? GitHubRepository(repository))?.label ?? repository
    }
}

#Preview {
    // Not on github.com, so the preview doesn't ask GitHub for commits.
    @Previewable @State var git = ApplicationSource(
        kind: .git(repository: "https://gitlab.example.com/shop/api.git"), branch: "main", isPinned: true,
        commit: "528a020f525ac31684b4fe5b019f9f2f2154e7f3")
    @Previewable @State var image = ApplicationSource(kind: .image(name: "traefik/whoami"), tag: "v1.11.0")
    Form {
        SourceSection(source: $git)
        SourceSection(source: $image)
    }
    .formStyle(.grouped)
    .frame(width: 520, height: 720)
}

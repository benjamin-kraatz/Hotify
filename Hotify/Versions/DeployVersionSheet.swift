import CoolifyAPI
import SwiftUI

/// Deploys one commit or image tag of an application, once or pinned. On GitHub it lists the branch's recent commits
/// to pick from. A commit Coolify still has an image of offers the faster rollback instead.
struct DeployVersionSheet: View {
    var resourceName: String
    var keptImages: [RollbackImage]
    var onRollBack: (RollbackImage) -> Void
    /// The deployment that queued, and the version it deploys.
    var onDeployed: (DeployedVersion, ApplicationVersion) -> Void

    @State private var model: DeployVersionModel
    @State private var commit = ""
    @State private var tag = ""
    @State private var keepsPinned = false
    @SwiftUI.Environment(\.dismiss) private var dismiss

    init(
        model: DeployVersionModel,
        resourceName: String,
        keptImages: [RollbackImage] = [],
        onRollBack: @escaping (RollbackImage) -> Void = { _ in },
        onDeployed: @escaping (DeployedVersion, ApplicationVersion) -> Void = { _, _ in }
    ) {
        _model = State(initialValue: model)
        self.resourceName = resourceName
        self.keptImages = keptImages
        self.onRollBack = onRollBack
        self.onDeployed = onDeployed
    }

    private var version: ApplicationVersion? {
        guard let source = model.source else { return nil }
        if source.isImage {
            let tag = tag.trimmingCharacters(in: .whitespaces)
            return ApplicationSource.isTag(tag) ? .imageTag(tag) : nil
        }
        let commit = commit.trimmingCharacters(in: .whitespaces)
        return ApplicationSource.isCommit(commit) ? .commit(commit) : nil
    }

    /// The kept image of the typed or picked commit.
    private var keptImage: RollbackImage? {
        keptImages.first { $0.matches(commit: commit.trimmingCharacters(in: .whitespaces)) }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Deploy a Version")
                #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Deploy") { deploy() }
                            .disabled(version == nil || model.isDeploying)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 540, idealHeight: 620)
        #endif
        .task {
            await model.load()
            if tag.isEmpty, model.source?.isImage == true { tag = model.source?.tag ?? "" }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let source = model.source {
            form(source)
        } else if let loadError = model.loadError {
            ContentUnavailableView {
                Label("Couldn't read \(resourceName)", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError)
            } actions: {
                Button("Try Again") { Task { await model.load() } }
                    .glassButton()
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func form(_ source: ApplicationSource) -> some View {
        Form {
            Section {
                if source.isImage {
                    TextField("Tag", text: $tag, prompt: Text("1.4.2"))
                        .autocorrectionDisabled()
                } else {
                    TextField("Commit", text: $commit, prompt: Text("528a020"))
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                }
            } header: {
                Text(source.isImage ? "Image Tag" : "Commit")
            } footer: {
                if !source.isImage, source.gitHubRepository == nil {
                    Text("Paste the SHA of the commit to deploy.")
                }
            }

            if !source.isImage, let repository = source.gitHubRepository, !source.trimmedBranch.isEmpty {
                CommitList(
                    repository: repository, branch: source.trimmedBranch, selection: $commit, keptImages: keptImages)
            }

            if let keptImage {
                Section {
                    if keptImage.isCurrent {
                        Text("This commit's image is the one running now.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Coolify kept this commit's image. Rolling back is faster than a new build.")
                        Button("Roll Back Instead", systemImage: "arrow.uturn.backward") {
                            onRollBack(keptImage)
                            dismiss()
                        }
                    }
                }
            }

            Section {
                Toggle("Keep it pinned", isOn: $keepsPinned)
            } footer: {
                Text(pinFooter(source))
            }

            if let error = model.error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.glow)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(model.isDeploying)
    }

    private func pinFooter(_ source: ApplicationSource) -> String {
        if keepsPinned {
            if source.isImage {
                return "Redeploy keeps pulling this tag until you change it in Settings."
            }
            // Coolify's push webhook deploys the pushed commit and never reads the pin.
            return source.deploysOnPush
                ? "Redeploy keeps building this commit until you change it in Settings. A push still deploys the pushed commit."
                : "Redeploy keeps building this commit until you change it in Settings."
        }
        return "Deploys it once. Redeploy goes back to \(previousDescription(source))."
    }

    private func previousDescription(_ source: ApplicationSource) -> String {
        switch model.previous {
        case .imageTag(let tag): tag
        case .commit(let sha) where sha.uppercased() != "HEAD": String(sha.prefix(7))
        default: source.trimmedBranch.isEmpty ? "the latest commit" : "the latest on \(source.trimmedBranch)"
        }
    }

    private func deploy() {
        guard let version else { return }
        Task {
            guard let deployed = await model.deploy(version, keepsPinned: keepsPinned) else { return }
            onDeployed(deployed, version)
            dismiss()
        }
    }
}

#Preview {
    DeployVersionSheet(
        model: DeployVersionModel(
            client: nil, application: "web",
            source: ApplicationSource(
                kind: .git(repository: "https://gitlab.example.com/shop/api.git"), branch: "main")),
        resourceName: "api",
        keptImages: [RollbackImage(tag: "528a020f525ac31684b4fe5b019f9f2f2154e7f3")]
    )
}

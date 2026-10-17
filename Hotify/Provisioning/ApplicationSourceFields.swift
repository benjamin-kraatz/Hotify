import CoolifyAPI
import SwiftUI

/// The form sections that say where a new application's code comes from: a repository and branch, a Dockerfile, an
/// image, or a repository behind a GitHub App or deploy key. They sit in the application's own screen, or in the Mac
/// sheet's middle column beside the inspector.
struct ApplicationSourceFields: View {
    var source: NewApplicationSource
    var model: ApplicationProvisioningModel

    var body: some View {
        switch source {
        case .publicGit: publicGitFields
        case .dockerfile: dockerfileFields
        case .dockerImage: dockerImageFields
        case .githubApp: githubFields
        case .deployKey: deployKeyFields
        }
    }

    private var publicGitFields: some View {
        @Bindable var model = model
        return Section {
            TextField(
                "Repository", text: $model.repository, prompt: Text(verbatim: "https://github.com/owner/name")
            )
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            TextField("Branch", text: $model.branch, prompt: Text(verbatim: "main"))
                .autocorrectionDisabled()
                #if os(iOS)
            .textInputAutocapitalization(.never)
                #endif
            buildPackPicker
        } header: {
            Text("Repository")
        } footer: {
            Text("How Coolify builds this repository.")
        }
    }

    private var dockerfileFields: some View {
        @Bindable var model = model
        return Section {
            TextField(
                "Dockerfile",
                text: $model.dockerfile,
                prompt: Text(verbatim: "FROM node:22\nCMD [\"node\", \"index.js\"]"),
                axis: .vertical
            )
            .font(.body.monospaced())
            .lineLimit(6...16)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
        } header: {
            Text("Dockerfile")
        } footer: {
            Text("The Dockerfile itself. Coolify builds it on the server.")
        }
    }

    private var dockerImageFields: some View {
        @Bindable var model = model
        return Section {
            TextField("Image", text: $model.imageName, prompt: Text(verbatim: "ghcr.io/org/app"))
                .font(.body.monospaced())
                .autocorrectionDisabled()
                #if os(iOS)
            .textInputAutocapitalization(.never)
                #endif
            TextField("Tag", text: $model.imageTag, prompt: Text(verbatim: "latest"))
                .font(.body.monospaced())
                .autocorrectionDisabled()
                #if os(iOS)
            .textInputAutocapitalization(.never)
                #endif
        } header: {
            Text("Image")
        } footer: {
            Text("Leave the tag empty for the one Coolify uses, usually latest.")
        }
    }

    private var githubFields: some View {
        @Bindable var model = model
        return Section {
            if model.isLoadingSource {
                loading("Loading GitHub Apps…")
            } else if model.sourceProblem != nil, model.githubApps.isEmpty {
                Text("GitHub Apps didn't load.")
                    .foregroundStyle(.secondary)
            } else if model.githubApps.isEmpty {
                Text("This instance has no GitHub App. Add one in Coolify, then pick it here.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("GitHub App", selection: $model.selectedGitHubAppID) {
                    Text("Choose").tag(Int?.none)
                    ForEach(model.githubApps) { app in
                        Text(appTitle(app)).tag(Optional(app.id))
                    }
                }
                .onChange(of: model.selectedGitHubAppID) { _, _ in model.githubAppChanged() }
                repositoryPicker
            }
        } header: {
            Text("Repository")
        }
    }

    @ViewBuilder
    private var repositoryPicker: some View {
        @Bindable var model = model
        if model.selectedGitHubAppID == nil {
            EmptyView()
        } else if model.isLoadingRepositories {
            loading("Loading repositories…")
        } else if model.repositories.isEmpty {
            Text(
                model.sourceProblem == nil
                    ? "That GitHub App has no repositories Hotify can see." : "Repositories didn't load."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Picker("Repository", selection: $model.selectedRepositoryFullName) {
                Text("Choose").tag(String?.none)
                ForEach(model.repositories) { repository in
                    Text(verbatim: repository.fullName).tag(Optional(repository.fullName))
                }
            }
            .onChange(of: model.selectedRepositoryFullName) { _, _ in model.repositoryChanged() }
            branchPicker
            buildPackPicker
        }
    }

    @ViewBuilder
    private var branchPicker: some View {
        @Bindable var model = model
        if model.selectedRepositoryFullName == nil {
            EmptyView()
        } else if model.isLoadingBranches {
            loading("Loading branches…")
        } else if model.branches.isEmpty {
            Text(model.sourceProblem == nil ? "That repository has no branches." : "Branches didn't load.")
                .foregroundStyle(.secondary)
        } else {
            Picker("Branch", selection: $model.branch) {
                ForEach(model.branches) { branch in
                    Text(verbatim: branch.name).tag(branch.name)
                }
            }
        }
    }

    private var deployKeyFields: some View {
        @Bindable var model = model
        return Section {
            if model.isLoadingSource {
                loading("Loading deploy keys…")
            } else if model.sourceProblem != nil, model.privateKeys.isEmpty {
                Text("Deploy keys didn't load.")
                    .foregroundStyle(.secondary)
            } else if model.privateKeys.isEmpty {
                Text("This instance has no deploy keys. Add one under Keys & Tokens in Coolify, then pick it here.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("Key", selection: $model.selectedKeyUUID) {
                    Text("Choose").tag(String?.none)
                    ForEach(model.privateKeys) { key in
                        Text(keyTitle(key)).tag(Optional(key.uuid))
                    }
                }
                TextField(
                    "Repository", text: $model.repository, prompt: Text(verbatim: "git@github.com:owner/name.git")
                )
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                TextField("Branch", text: $model.branch, prompt: Text(verbatim: "main"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                .textInputAutocapitalization(.never)
                    #endif
                buildPackPicker
            }
        } header: {
            Text("Repository")
        } footer: {
            Text("The key stays on Coolify. Hotify only sends which one to use.")
        }
    }

    private var buildPackPicker: some View {
        @Bindable var model = model
        return Picker("Build pack", selection: $model.buildPack) {
            ForEach(ApplicationBuildPack.allCases) { pack in
                Text(pack.displayName).tag(pack)
            }
        }
    }

    private func loading(_ title: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .foregroundStyle(.secondary)
        }
    }

    private func appTitle(_ app: GitHubApp) -> String {
        let trimmed = app.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? app.uuid : trimmed
    }

    private func keyTitle(_ key: PrivateKeySummary) -> String {
        let trimmed = key.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? key.uuid : trimmed
    }
}

#Preview {
    let model = ApplicationProvisioningModel(placement: PlacementModel())
    model.source = .publicGit
    return Form {
        ApplicationSourceFields(source: .publicGit, model: model)
    }
    .formStyle(.grouped)
    .frame(width: 520, height: 400)
}

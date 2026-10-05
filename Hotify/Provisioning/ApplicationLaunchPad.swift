import CoolifyAPI
import SwiftUI

/// One application source, up close: where it should run, the fields that source needs, and whether to deploy it now.
struct ApplicationLaunchPad: View {
    var source: NewApplicationSource
    var model: ApplicationProvisioningModel
    var instanceRoot: URL?

    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var model = model

        Form {
            Section {
            } header: {
                hero
            }

            PlacementSection(model: model.placement)

            sourceSection

            Section {
                TextField("Name", text: $model.name, prompt: Text("Optional"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                .textInputAutocapitalization(.never)
                    #endif
                if source == .publicGit {
                    TextField("Description", text: $model.description, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(1...3)
                }
                NumberField(title: "Exposed port", value: $model.port, prompt: "3000")
            } header: {
                Text("Name")
            } footer: {
                Text("Leave the port empty and Coolify chooses one. A name you leave empty is filled in for you.")
            }

            Section {
                Toggle("Deploy immediately", isOn: $model.instantDeploy)
            } footer: {
                Text(
                    model.instantDeploy
                        ? "Coolify builds and starts it as soon as it exists."
                        : "Coolify creates it and leaves it stopped."
                )
            }

            if let problem = model.createProblem ?? model.sourceProblem ?? model.placement.problem {
                Section {
                    ProblemNotice(problem: problem, instanceRoot: instanceRoot)
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) { createBar }
        .disabled(model.isCreating)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy, value: model.instantDeploy)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy, value: model.createProblem)
        .onChange(of: model.placement.placement) { _, _ in model.createProblem = nil }
        .task {
            // The gallery sets this too. The task repeats it so the catalog load cannot race the first frame.
            model.source = source
            await model.loadCatalog()
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 18) {
            TemplateLogo(name: source.title, url: nil, size: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text(source.title)
                    .font(.display(.title))
                    .foregroundStyle(.primary)
                Text(source.slogan)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textCase(nil)
        .padding(.bottom, 14)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var sourceSection: some View {
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

    private var createBar: some View {
        HStack(spacing: 14) {
            FlameGlyph(heat: model.isCreating ? .warming : .cold, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.statusLine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(model.problem == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.glow))
                    .contentTransition(.interpolate)
                Text(destinationSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Button {
                Task { await model.create() }
            } label: {
                Text(model.instantDeploy ? "Create and Deploy" : "Create")
                    .opacity(model.isCreating ? 0 : 1)
                    .overlay {
                        if model.isCreating {
                            ProgressView().controlSize(.small)
                        }
                    }
            }
            .glassButton(prominent: true)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canCreate)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy, value: model.isCreating)
    }

    private var destinationSummary: String {
        let placement = model.placement
        guard let server = placement.server, let project = placement.project, let environment = placement.environment
        else { return "Pick a server, project, and environment." }
        let place =
            "On \(server.name), in \(project.name ?? project.uuid) · \(environment.name ?? "")."
        if model.instantDeploy {
            return place + " It deploys right away."
        }
        return place + " It stays stopped until you start it."
    }
}

#Preview("Public repository") {
    launchPad(.publicGit)
}

#Preview("Dockerfile") {
    launchPad(.dockerfile)
}

#Preview("GitHub App") {
    launchPad(.githubApp)
}

private func launchPad(_ source: NewApplicationSource) -> some View {
    let placement = PlacementModel(
        servers: [Server(uuid: "s1", name: "localhost", isReachable: true)],
        projects: [Project(uuid: "p1", name: "Website", environments: [Environment(uuid: "e1", name: "production")])],
        placement: Placement(serverUUID: "s1", projectUUID: "p1", environmentUUID: "e1")
    )
    let model = ApplicationProvisioningModel(placement: placement)
    model.source = source
    return NavigationStack {
        ApplicationLaunchPad(source: source, model: model)
    }
    .frame(width: 720, height: 760)
}

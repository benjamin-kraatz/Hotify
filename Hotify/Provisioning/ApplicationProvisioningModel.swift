import CoolifyAPI
import Foundation

/// Takes a source to a new application: place it, create it, and watch the first deploy when one was asked for.
@Observable
final class ApplicationProvisioningModel {
    let placement: PlacementModel
    var source: ApplicationSource = .publicGit

    var name = ""
    var description = ""
    var repository = ""
    var branch = "main"
    var buildPack: ApplicationBuildPack = .nixpacks
    var dockerfile = ""
    var imageName = ""
    var imageTag = ""
    var port: Int?
    var instantDeploy = true

    var githubApps: [GitHubApp] = []
    var selectedGitHubAppID: Int?
    var repositories: [GitHubAppRepository] = []
    var selectedRepositoryFullName: String?
    var branches: [GitHubAppBranch] = []

    var privateKeys: [PrivateKeySummary] = []
    var selectedKeyUUID: String?

    private(set) var isLoadingSource = false
    private(set) var isLoadingRepositories = false
    private(set) var isLoadingBranches = false
    var sourceProblem: ProvisioningProblem?

    private(set) var isCreating = false
    var createProblem: ProvisioningProblem?
    private(set) var created: CreatedResource?
    var ignition = Ignition()

    private var client: CoolifyClient?

    init(placement: PlacementModel) {
        self.placement = placement
    }

    func prepare(_ client: CoolifyClient?) {
        self.client = client
    }

    var route: ResourceRoute? { created.map { .application($0.uuid) } }

    var displayName: String {
        if let trimmed = trimmed(name) { return trimmed }
        switch source {
        case .publicGit, .deployKey:
            return repositoryLabel(repository) ?? "Application"
        case .dockerfile:
            return "Application"
        case .dockerImage:
            return trimmed(imageName) ?? "Application"
        case .githubApp:
            return selectedRepository?.name ?? "Application"
        }
    }

    var selectedGitHubApp: GitHubApp? { githubApps.first { $0.id == selectedGitHubAppID } }

    var selectedRepository: GitHubAppRepository? {
        repositories.first { $0.fullName == selectedRepositoryFullName }
    }

    /// What Coolify would refuse, worded for the person filling the form.
    ///
    /// A missing field waits until the placement is complete, so the bar asks for a server first. A value that is
    /// already wrong, such as a port of 0, is said at once.
    var problem: String? {
        if let port, !(1...65_535).contains(port) { return "A port is a number from 1 to 65535." }
        if source == .dockerImage, let image = trimmed(imageName), image.contains(" ") {
            return "An image has no spaces, such as ghcr.io/org/app."
        }
        if source == .dockerImage, let tag = trimmed(imageTag), tag.contains(" ") {
            return "A tag has no spaces, such as latest."
        }
        if isLoadingSource || isLoadingRepositories || isLoadingBranches { return nil }
        guard placement.placement.isComplete else { return nil }
        switch source {
        case .publicGit:
            if trimmed(repository) == nil { return "A repository URL is needed." }
            if trimmed(branch) == nil { return "A branch is needed." }
        case .dockerfile:
            if trimmed(dockerfile) == nil { return "A Dockerfile is needed." }
        case .dockerImage:
            if trimmed(imageName) == nil { return "An image name is needed." }
        case .githubApp:
            if sourceProblem != nil { return "The list didn't load." }
            if githubApps.isEmpty { return "This instance has no GitHub App." }
            if selectedGitHubApp == nil { return "Pick a GitHub App." }
            if repositories.isEmpty { return "That GitHub App has no repositories." }
            if selectedRepository == nil { return "Pick a repository." }
            if branches.isEmpty { return "That repository has no branches." }
            if trimmed(branch) == nil { return "Pick a branch." }
        case .deployKey:
            if sourceProblem != nil { return "The list didn't load." }
            if privateKeys.isEmpty { return "This instance has no deploy keys." }
            if selectedKeyUUID == nil { return "Pick a deploy key." }
            if trimmed(repository) == nil { return "A repository URL is needed." }
            if trimmed(branch) == nil { return "A branch is needed." }
        }
        return nil
    }

    var statusLine: String {
        if isCreating { return "Creating \(displayName)…" }
        if let problem { return problem }
        if isLoadingSource || isLoadingRepositories || isLoadingBranches { return "Loading…" }
        return "Ready to create"
    }

    var canCreate: Bool {
        client != nil && placement.placement.isComplete && !isCreating && !placement.isCreatingPlace
            && !placement.isLoadingDestinations && !isLoadingSource && !isLoadingRepositories
            && !isLoadingBranches && problem == nil
    }

    /// Loads GitHub Apps or deploy keys for the sources that pick from a list.
    func loadCatalog() async {
        switch source {
        case .githubApp: await loadGitHubApps()
        case .deployKey: await loadDeployKeys()
        case .publicGit, .dockerfile, .dockerImage: break
        }
    }

    private func loadGitHubApps() async {
        guard let client else { return }
        isLoadingSource = true
        defer { isLoadingSource = false }
        do {
            let loaded = try await client.githubApps()
            githubApps = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            sourceProblem = nil
        } catch is CancellationError {
            return
        } catch {
            githubApps = []
            sourceProblem = ProvisioningProblem(error)
        }
    }

    private func loadDeployKeys() async {
        guard let client else { return }
        isLoadingSource = true
        defer { isLoadingSource = false }
        do {
            let loaded = try await client.privateKeys()
            privateKeys = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            sourceProblem = nil
        } catch is CancellationError {
            return
        } catch {
            privateKeys = []
            sourceProblem = ProvisioningProblem(error)
        }
    }

    func githubAppChanged() {
        repositories = []
        branches = []
        selectedRepositoryFullName = nil
        branch = "main"
        sourceProblem = nil
        guard selectedGitHubAppID != nil else { return }
        Task { await loadRepositories() }
    }

    func repositoryChanged() {
        branches = []
        branch = selectedRepository?.defaultBranch ?? "main"
        sourceProblem = nil
        guard selectedRepository != nil else { return }
        Task { await loadBranches() }
    }

    func loadRepositories() async {
        guard let client, let appID = selectedGitHubAppID else {
            repositories = []
            return
        }
        isLoadingRepositories = true
        defer { isLoadingRepositories = false }
        do {
            let loaded = try await client.githubRepositories(appID: appID)
            guard selectedGitHubAppID == appID else { return }
            repositories = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            sourceProblem = nil
        } catch is CancellationError {
            return
        } catch {
            guard selectedGitHubAppID == appID else { return }
            repositories = []
            sourceProblem = ProvisioningProblem(error)
        }
    }

    func loadBranches() async {
        guard let client, let appID = selectedGitHubAppID, let repository = selectedRepository else {
            branches = []
            return
        }
        let fullName = repository.fullName
        isLoadingBranches = true
        defer { isLoadingBranches = false }
        do {
            let loaded = try await client.githubBranches(
                appID: appID, owner: repository.owner, repo: repository.repositoryName)
            guard selectedRepositoryFullName == fullName else { return }
            branches = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            // Keep a default branch the repository actually has. Otherwise the picker would sit on a value it
            // cannot show.
            if !branches.contains(where: { $0.name == branch }), let first = branches.first {
                branch = first.name
            }
            sourceProblem = nil
        } catch is CancellationError {
            return
        } catch {
            guard selectedRepositoryFullName == fullName else { return }
            branches = []
            sourceProblem = ProvisioningProblem(error)
        }
    }

    /// Creates the application. When instant deploy is on, `watch` follows the first start.
    func create() async {
        guard let client, canCreate,
            let serverUUID = placement.placement.serverUUID,
            let projectUUID = placement.placement.projectUUID,
            let environmentUUID = placement.placement.environmentUUID
        else { return }
        isCreating = true
        createProblem = nil
        defer { isCreating = false }
        do {
            created = try await submit(
                client, serverUUID: serverUUID, projectUUID: projectUUID, environmentUUID: environmentUUID)
            placement.remember()
            ignition = Ignition()
        } catch is CancellationError {
            return
        } catch {
            createProblem = ProvisioningProblem(error)
        }
    }

    /// Polls the application until it runs. A create that left it stopped does not wait.
    func watch() async {
        guard instantDeploy, let client, let uuid = created?.uuid else { return }
        while !Task.isCancelled, ignition.phase != .running {
            if let application = try? await client.application(uuid) {
                ignition.observe(application, name: displayName)
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func submit(
        _ client: CoolifyClient, serverUUID: String, projectUUID: String, environmentUUID: String
    ) async throws -> CreatedResource {
        let destinationUUID = placement.placement.destinationUUID
        let ports = port.map(String.init)
        switch source {
        case .publicGit:
            return try await client.createPublicApplication(
                PublicApplicationDraft(
                    projectUUID: projectUUID,
                    serverUUID: serverUUID,
                    environmentUUID: environmentUUID,
                    destinationUUID: destinationUUID,
                    name: trimmed(name),
                    description: trimmed(description),
                    portsExposes: ports,
                    instantDeploy: instantDeploy,
                    gitRepository: trimmed(repository) ?? "",
                    gitBranch: trimmed(branch) ?? "main",
                    buildPack: buildPack
                ))
        case .dockerfile:
            return try await client.createDockerfileApplication(
                DockerfileApplicationDraft(
                    projectUUID: projectUUID,
                    serverUUID: serverUUID,
                    environmentUUID: environmentUUID,
                    destinationUUID: destinationUUID,
                    name: trimmed(name),
                    portsExposes: ports,
                    instantDeploy: instantDeploy,
                    dockerfile: trimmed(dockerfile) ?? ""
                ))
        case .dockerImage:
            return try await client.createDockerImageApplication(
                DockerImageApplicationDraft(
                    projectUUID: projectUUID,
                    serverUUID: serverUUID,
                    environmentUUID: environmentUUID,
                    destinationUUID: destinationUUID,
                    name: trimmed(name),
                    portsExposes: ports,
                    instantDeploy: instantDeploy,
                    dockerRegistryImageName: trimmed(imageName) ?? "",
                    dockerRegistryImageTag: trimmed(imageTag)
                ))
        case .githubApp:
            return try await client.createPrivateGitHubAppApplication(
                PrivateGitHubAppApplicationDraft(
                    projectUUID: projectUUID,
                    serverUUID: serverUUID,
                    environmentUUID: environmentUUID,
                    destinationUUID: destinationUUID,
                    name: trimmed(name),
                    portsExposes: ports,
                    instantDeploy: instantDeploy,
                    githubAppUUID: selectedGitHubApp?.uuid ?? "",
                    gitRepository: selectedRepository?.fullName ?? "",
                    gitBranch: trimmed(branch) ?? "main",
                    buildPack: buildPack
                ))
        case .deployKey:
            return try await client.createDeployKeyApplication(
                DeployKeyApplicationDraft(
                    projectUUID: projectUUID,
                    serverUUID: serverUUID,
                    environmentUUID: environmentUUID,
                    destinationUUID: destinationUUID,
                    name: trimmed(name),
                    portsExposes: ports,
                    instantDeploy: instantDeploy,
                    privateKeyUUID: selectedKeyUUID ?? "",
                    gitRepository: trimmed(repository) ?? "",
                    gitBranch: trimmed(branch) ?? "main",
                    buildPack: buildPack
                ))
        }
    }

    private func trimmed(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func repositoryLabel(_ url: String) -> String? {
        guard var last = trimmed(url)?.split(separator: "/").last.map(String.init) else { return nil }
        if last.hasSuffix(".git") { last.removeLast(4) }
        return last.isEmpty ? nil : last
    }
}

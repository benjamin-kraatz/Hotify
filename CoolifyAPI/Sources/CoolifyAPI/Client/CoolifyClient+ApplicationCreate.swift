import Foundation

extension CoolifyClient {
    /// Creates an application from a public Git repository. A nil optional stays out of the body, and only
    /// `environment_uuid` is sent for the environment.
    public func createPublicApplication(_ draft: PublicApplicationDraft) async throws -> CreatedResource {
        try await post("applications/public", body: draft)
    }

    /// Creates an application from Dockerfile text. `build_pack` is `dockerfile`.
    public func createDockerfileApplication(_ draft: DockerfileApplicationDraft) async throws -> CreatedResource {
        try await post("applications/dockerfile", body: draft)
    }

    /// Creates an application that runs an image already in a registry. The tag stays out when nil, and no
    /// `build_pack` is sent.
    public func createDockerImageApplication(_ draft: DockerImageApplicationDraft) async throws -> CreatedResource {
        try await post("applications/dockerimage", body: draft)
    }

    /// Creates an application from a repository a GitHub App on this instance can see.
    ///
    /// `draft.gitRepository` is `owner/name`. The app is named by its uuid, while the repository routes take the
    /// numeric id from `githubApps()`.
    public func createPrivateGitHubAppApplication(_ draft: PrivateGitHubAppApplicationDraft) async throws
        -> CreatedResource
    {
        try await post("applications/private-github-app", body: draft)
    }

    /// Creates an application cloned with a deploy key this instance already has. The key is not created here.
    public func createDeployKeyApplication(_ draft: DeployKeyApplicationDraft) async throws -> CreatedResource {
        try await post("applications/private-deploy-key", body: draft)
    }

    public func githubApps() async throws -> [GitHubApp] {
        try await getList("github-apps")
    }

    /// Repositories the GitHub App can see. `appID` is `GitHubApp.id`, not its uuid. Coolify wraps the list.
    public func githubRepositories(appID: Int) async throws -> [GitHubAppRepository] {
        let path = "github-apps/\(CoolifyURL.encodePathComponent(String(appID)))/repositories"
        let payload: GitHubRepositoryList = try await get(path)
        return payload.repositories.filter { !$0.fullName.isEmpty || !$0.name.isEmpty }
    }

    /// Branches of one repository. `appID` is `GitHubApp.id`. Coolify wraps the list.
    public func githubBranches(appID: Int, owner: String, repo: String) async throws -> [GitHubAppBranch] {
        let app = CoolifyURL.encodePathComponent(String(appID))
        let owner = CoolifyURL.encodePathComponent(owner)
        let repo = CoolifyURL.encodePathComponent(repo)
        let payload: GitHubBranchList = try await get(
            "github-apps/\(app)/repositories/\(owner)/\(repo)/branches")
        return payload.branches.filter { !$0.name.isEmpty }
    }

    /// Keys this instance already has, as uuid and name. Nothing here creates a key or reads its material.
    public func privateKeys() async throws -> [PrivateKeySummary] {
        try await getList("security/keys")
    }
}

private struct GitHubRepositoryList: Decodable {
    var repositories: [GitHubAppRepository]

    enum CodingKeys: String, CodingKey {
        case repositories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        repositories = try container.decodeIfPresent([GitHubAppRepository].self, forKey: .repositories) ?? []
    }
}

private struct GitHubBranchList: Decodable {
    var branches: [GitHubAppBranch]

    enum CodingKeys: String, CodingKey {
        case branches
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        branches = try container.decodeIfPresent([GitHubAppBranch].self, forKey: .branches) ?? []
    }
}

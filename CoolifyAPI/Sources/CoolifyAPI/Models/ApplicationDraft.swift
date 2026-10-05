import Foundation

/// The body for `POST /applications/public`.
///
/// Optional fields stay out of the JSON when `nil`. `environment_name` is never sent: the uuid is enough.
public struct PublicApplicationDraft: Encodable, Sendable, Hashable {
    public var placement: ApplicationPlacement
    public var gitRepository: String
    public var gitBranch: String
    public var buildPack: ApplicationBuildPack
    /// Comma-separated URLs.
    public var domains: String?
    /// Path of the Dockerfile in the repository. Coolify's default is `/Dockerfile`.
    public var dockerfileLocation: String?
    /// Path of the compose file when `buildPack` is `dockercompose`.
    public var dockerComposeLocation: String?

    enum CodingKeys: String, CodingKey {
        case gitRepository
        case gitBranch
        case buildPack
        case domains
        case dockerfileLocation
        case dockerComposeLocation
    }

    public init(
        projectUUID: String,
        serverUUID: String,
        environmentUUID: String,
        destinationUUID: String? = nil,
        name: String? = nil,
        description: String? = nil,
        portsExposes: String? = nil,
        instantDeploy: Bool = true,
        gitRepository: String,
        gitBranch: String,
        buildPack: ApplicationBuildPack,
        domains: String? = nil,
        dockerfileLocation: String? = nil,
        dockerComposeLocation: String? = nil
    ) {
        placement = ApplicationPlacement(
            projectUUID: projectUUID,
            serverUUID: serverUUID,
            environmentUUID: environmentUUID,
            destinationUUID: destinationUUID,
            name: name,
            description: description,
            portsExposes: portsExposes,
            instantDeploy: instantDeploy
        )
        self.gitRepository = gitRepository
        self.gitBranch = gitBranch
        self.buildPack = buildPack
        self.domains = domains
        self.dockerfileLocation = dockerfileLocation
        self.dockerComposeLocation = dockerComposeLocation
    }

    public func encode(to encoder: Encoder) throws {
        try placement.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(gitRepository, forKey: .gitRepository)
        try container.encode(gitBranch, forKey: .gitBranch)
        try container.encode(buildPack, forKey: .buildPack)
        try container.encodeIfPresent(domains, forKey: .domains)
        try container.encodeIfPresent(dockerfileLocation, forKey: .dockerfileLocation)
        try container.encodeIfPresent(dockerComposeLocation, forKey: .dockerComposeLocation)
    }
}

/// The body for `POST /applications/dockerfile`. `build_pack` is always `dockerfile`.
public struct DockerfileApplicationDraft: Encodable, Sendable, Hashable {
    public var placement: ApplicationPlacement
    /// The Dockerfile itself, not a path.
    public var dockerfile: String

    enum CodingKeys: String, CodingKey {
        case dockerfile
        case buildPack
    }

    public init(
        projectUUID: String,
        serverUUID: String,
        environmentUUID: String,
        destinationUUID: String? = nil,
        name: String? = nil,
        description: String? = nil,
        portsExposes: String? = nil,
        instantDeploy: Bool = true,
        dockerfile: String
    ) {
        placement = ApplicationPlacement(
            projectUUID: projectUUID,
            serverUUID: serverUUID,
            environmentUUID: environmentUUID,
            destinationUUID: destinationUUID,
            name: name,
            description: description,
            portsExposes: portsExposes,
            instantDeploy: instantDeploy
        )
        self.dockerfile = dockerfile
    }

    public func encode(to encoder: Encoder) throws {
        try placement.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dockerfile, forKey: .dockerfile)
        // The dockerfile endpoint's build pack enum has this one value.
        try container.encode(ApplicationBuildPack.dockerfile, forKey: .buildPack)
    }
}

/// The body for `POST /applications/dockerimage`.
///
/// Coolify 4.3's schema for this endpoint has no `build_pack` key and answers 422 for one, so it stays out.
public struct DockerImageApplicationDraft: Encodable, Sendable, Hashable {
    public var placement: ApplicationPlacement
    public var dockerRegistryImageName: String
    public var dockerRegistryImageTag: String?

    enum CodingKeys: String, CodingKey {
        case dockerRegistryImageName
        case dockerRegistryImageTag
    }

    public init(
        projectUUID: String,
        serverUUID: String,
        environmentUUID: String,
        destinationUUID: String? = nil,
        name: String? = nil,
        description: String? = nil,
        portsExposes: String? = nil,
        instantDeploy: Bool = true,
        dockerRegistryImageName: String,
        dockerRegistryImageTag: String? = nil
    ) {
        placement = ApplicationPlacement(
            projectUUID: projectUUID,
            serverUUID: serverUUID,
            environmentUUID: environmentUUID,
            destinationUUID: destinationUUID,
            name: name,
            description: description,
            portsExposes: portsExposes,
            instantDeploy: instantDeploy
        )
        self.dockerRegistryImageName = dockerRegistryImageName
        self.dockerRegistryImageTag = dockerRegistryImageTag
    }

    public func encode(to encoder: Encoder) throws {
        try placement.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dockerRegistryImageName, forKey: .dockerRegistryImageName)
        try container.encodeIfPresent(dockerRegistryImageTag, forKey: .dockerRegistryImageTag)
    }
}

/// The body for `POST /applications/private-github-app`.
public struct PrivateGitHubAppApplicationDraft: Encodable, Sendable, Hashable {
    public var placement: ApplicationPlacement
    public var githubAppUUID: String
    /// `owner/name`, the form Coolify stores for a GitHub App repository.
    public var gitRepository: String
    public var gitBranch: String
    public var buildPack: ApplicationBuildPack

    enum CodingKeys: String, CodingKey {
        case githubAppUUID = "githubAppUuid"
        case gitRepository
        case gitBranch
        case buildPack
    }

    public init(
        projectUUID: String,
        serverUUID: String,
        environmentUUID: String,
        destinationUUID: String? = nil,
        name: String? = nil,
        description: String? = nil,
        portsExposes: String? = nil,
        instantDeploy: Bool = true,
        githubAppUUID: String,
        gitRepository: String,
        gitBranch: String,
        buildPack: ApplicationBuildPack
    ) {
        placement = ApplicationPlacement(
            projectUUID: projectUUID,
            serverUUID: serverUUID,
            environmentUUID: environmentUUID,
            destinationUUID: destinationUUID,
            name: name,
            description: description,
            portsExposes: portsExposes,
            instantDeploy: instantDeploy
        )
        self.githubAppUUID = githubAppUUID
        self.gitRepository = gitRepository
        self.gitBranch = gitBranch
        self.buildPack = buildPack
    }

    public func encode(to encoder: Encoder) throws {
        try placement.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(githubAppUUID, forKey: .githubAppUUID)
        try container.encode(gitRepository, forKey: .gitRepository)
        try container.encode(gitBranch, forKey: .gitBranch)
        try container.encode(buildPack, forKey: .buildPack)
    }
}

/// The body for `POST /applications/private-deploy-key`. The key is one Coolify already has.
public struct DeployKeyApplicationDraft: Encodable, Sendable, Hashable {
    public var placement: ApplicationPlacement
    public var privateKeyUUID: String
    public var gitRepository: String
    public var gitBranch: String
    public var buildPack: ApplicationBuildPack

    enum CodingKeys: String, CodingKey {
        case privateKeyUUID = "privateKeyUuid"
        case gitRepository
        case gitBranch
        case buildPack
    }

    public init(
        projectUUID: String,
        serverUUID: String,
        environmentUUID: String,
        destinationUUID: String? = nil,
        name: String? = nil,
        description: String? = nil,
        portsExposes: String? = nil,
        instantDeploy: Bool = true,
        privateKeyUUID: String,
        gitRepository: String,
        gitBranch: String,
        buildPack: ApplicationBuildPack
    ) {
        placement = ApplicationPlacement(
            projectUUID: projectUUID,
            serverUUID: serverUUID,
            environmentUUID: environmentUUID,
            destinationUUID: destinationUUID,
            name: name,
            description: description,
            portsExposes: portsExposes,
            instantDeploy: instantDeploy
        )
        self.privateKeyUUID = privateKeyUUID
        self.gitRepository = gitRepository
        self.gitBranch = gitBranch
        self.buildPack = buildPack
    }

    public func encode(to encoder: Encoder) throws {
        try placement.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(privateKeyUUID, forKey: .privateKeyUUID)
        try container.encode(gitRepository, forKey: .gitRepository)
        try container.encode(gitBranch, forKey: .gitBranch)
        try container.encode(buildPack, forKey: .buildPack)
    }
}

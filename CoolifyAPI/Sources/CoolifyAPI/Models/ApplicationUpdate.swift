import Foundation

/// How an application's proxy treats the `www.` and bare forms of its domains.
public enum DomainRedirect: String, Codable, Sendable, CaseIterable {
    /// Answers on both, without a redirect.
    case both
    /// Sends the bare domain to `www.`.
    case www
    /// Sends `www.` to the bare domain.
    case nonWWW = "non-www"
}

/// The domains of one service in a Docker Compose application. `domain` is comma-separated, and empty leaves the
/// service without one.
public struct ComposeDomain: Encodable, Sendable, Hashable {
    /// The service's name in the compose file.
    public var name: String
    public var domain: String

    public init(name: String, domain: String) {
        self.name = name
        self.domain = domain
    }
}

/// The body that changes an application. Fields left `nil` stay out of the JSON, so Coolify keeps them.
///
/// Coolify 4.3 answers 422 to any key it does not expect, and to `domains` on a Docker Compose application,
/// which takes `dockerComposeDomains` instead.
public struct ApplicationUpdate: Encodable, Sendable, Hashable {
    public var name: String?
    public var description: String?
    /// Comma-separated URLs. Empty removes every domain.
    public var domains: String?
    public var redirect: DomainRedirect?
    public var isForceHTTPSEnabled: Bool?
    /// Every service of a Docker Compose application. Coolify replaces the whole list, so a service left out
    /// loses its domains.
    public var dockerComposeDomains: [ComposeDomain]?
    /// Sent flat, as Coolify's `health_check_*` fields.
    public var healthCheck: HealthCheck?
    /// Takes a domain another resource already uses, after Coolify answered 409.
    public var forceDomainOverride: Bool?
    public var gitBranch: String?
    /// The commit manual deploys build. `HEAD` goes back to the branch's latest.
    public var gitCommitSHA: String?
    public var dockerRegistryImageTag: String?
    public var isAutoDeployEnabled: Bool?
    /// The proxy label block, as plain text. It is sent as base64. An empty string clears labels that were
    /// present. `nil` leaves them alone.
    public var customLabels: String?
    /// Whether Coolify turns `$` into `$$` in the labels. Off lets the labels expand environment variables.
    public var isContainerLabelEscapeEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case domains
        case redirect
        // snake_case conversion of `isForceHTTPSEnabled` would give `is_force_h_t_t_p_s_enabled`.
        case isForceHTTPSEnabled = "isForceHttpsEnabled"
        case dockerComposeDomains
        case forceDomainOverride
        case gitBranch
        case gitCommitSHA = "gitCommitSha"
        case dockerRegistryImageTag
        case isAutoDeployEnabled
        case customLabels
        case isContainerLabelEscapeEnabled
    }

    public init(
        name: String? = nil,
        description: String? = nil,
        domains: String? = nil,
        redirect: DomainRedirect? = nil,
        isForceHTTPSEnabled: Bool? = nil,
        dockerComposeDomains: [ComposeDomain]? = nil,
        healthCheck: HealthCheck? = nil,
        forceDomainOverride: Bool? = nil,
        gitBranch: String? = nil,
        gitCommitSHA: String? = nil,
        dockerRegistryImageTag: String? = nil,
        isAutoDeployEnabled: Bool? = nil,
        customLabels: String? = nil,
        isContainerLabelEscapeEnabled: Bool? = nil
    ) {
        self.name = name
        self.description = description
        self.domains = domains
        self.redirect = redirect
        self.isForceHTTPSEnabled = isForceHTTPSEnabled
        self.dockerComposeDomains = dockerComposeDomains
        self.healthCheck = healthCheck
        self.forceDomainOverride = forceDomainOverride
        self.gitBranch = gitBranch
        self.gitCommitSHA = gitCommitSHA
        self.dockerRegistryImageTag = dockerRegistryImageTag
        self.isAutoDeployEnabled = isAutoDeployEnabled
        self.customLabels = customLabels
        self.isContainerLabelEscapeEnabled = isContainerLabelEscapeEnabled
    }

    /// Whether there is anything to send.
    public var isEmpty: Bool {
        name == nil && description == nil && domains == nil && redirect == nil && isForceHTTPSEnabled == nil
            && dockerComposeDomains == nil && healthCheck == nil && gitBranch == nil && gitCommitSHA == nil
            && dockerRegistryImageTag == nil && isAutoDeployEnabled == nil && customLabels == nil
            && isContainerLabelEscapeEnabled == nil
    }

    /// Whether the change only reaches the running app with its next deployment. Coolify writes domains, the
    /// health check, and proxy labels into the container as it deploys, and builds a new version only then.
    public var needsRedeploy: Bool {
        domains != nil || redirect != nil || isForceHTTPSEnabled != nil || dockerComposeDomains != nil
            || healthCheck != nil || gitBranch != nil || gitCommitSHA != nil || dockerRegistryImageTag != nil
            || customLabels != nil || isContainerLabelEscapeEnabled != nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(domains, forKey: .domains)
        try container.encodeIfPresent(redirect, forKey: .redirect)
        try container.encodeIfPresent(isForceHTTPSEnabled, forKey: .isForceHTTPSEnabled)
        try container.encodeIfPresent(dockerComposeDomains, forKey: .dockerComposeDomains)
        try container.encodeIfPresent(forceDomainOverride, forKey: .forceDomainOverride)
        try container.encodeIfPresent(gitBranch, forKey: .gitBranch)
        try container.encodeIfPresent(gitCommitSHA, forKey: .gitCommitSHA)
        try container.encodeIfPresent(dockerRegistryImageTag, forKey: .dockerRegistryImageTag)
        try container.encodeIfPresent(isAutoDeployEnabled, forKey: .isAutoDeployEnabled)
        // The live API rejects `custom_labels` unless they are base64, which the OpenAPI spec does not mention.
        try container.encodeIfPresent(customLabels.map(Base64Text.encode), forKey: .customLabels)
        try container.encodeIfPresent(isContainerLabelEscapeEnabled, forKey: .isContainerLabelEscapeEnabled)
        try healthCheck?.encode(to: encoder)
    }
}

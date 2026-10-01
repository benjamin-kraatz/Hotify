import Foundation

/// Application flags. `is_force_https_enabled` becomes `isForceHttpsEnabled` after snake_case conversion,
/// which does not match a property spelled `isForceHTTPSEnabled`.
public struct ApplicationSettings: Decodable, Sendable, Hashable {
    public var isPreviewDeploymentsEnabled: Bool?
    public var isForceHTTPSEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case isPreviewDeploymentsEnabled
        case isForceHTTPSEnabled = "isForceHttpsEnabled"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isPreviewDeploymentsEnabled = container.flexBool(.isPreviewDeploymentsEnabled)
        isForceHTTPSEnabled = container.flexBool(.isForceHTTPSEnabled)
    }
}

/// A standalone Coolify application. Service containers use `ServiceApplication` instead.
public struct Application: Decodable, Sendable, Hashable, HasResourceStatus {
    public var id: Int?
    public var uuid: String
    public var name: String
    public var description: String?
    public var status: String?
    public var fqdn: String?
    public var gitRepository: String?
    public var gitBranch: String?
    public var buildPack: String?
    public var createdAt: String?
    public var settings: ApplicationSettings?
    /// How Coolify names a preview's domain, such as `{{pr_id}}.{{domain}}`.
    public var previewURLTemplate: String?
    /// The environment the application lives in. Match it against `Project.environments` to find its project.
    public var environmentID: Int?
    public var redirect: DomainRedirect?
    /// The domains of each service, by name, when the application builds from a Docker Compose file. Services
    /// that never had a domain are missing.
    public var dockerComposeDomains: [String: String]?
    public var healthCheck: HealthCheck?

    /// Whether the application builds from a Docker Compose file, whose domains are set per service.
    public var isDockerCompose: Bool { buildPack == "dockercompose" }

    public var createdAtDate: Date? { createdAt.flatMap(CoolifyTimestamp.parse) }

    enum CodingKeys: String, CodingKey {
        case id
        case uuid
        case name
        case description
        case status
        case fqdn
        case gitRepository
        case gitBranch
        case buildPack
        case createdAt
        case settings
        case previewURLTemplate = "previewUrlTemplate"
        case environmentID = "environmentId"
        case redirect
        case dockerComposeDomains
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.flexInt(.id)
        uuid = try container.decode(String.self, forKey: .uuid)
        name = container.flexString(.name) ?? ""
        description = container.flexString(.description)
        status = container.flexString(.status)
        fqdn = container.flexString(.fqdn)
        gitRepository = container.flexString(.gitRepository)
        gitBranch = container.flexString(.gitBranch)
        buildPack = container.flexString(.buildPack)
        createdAt = container.flexString(.createdAt)
        settings = try container.decodeIfPresent(ApplicationSettings.self, forKey: .settings)
        previewURLTemplate = container.flexString(.previewURLTemplate)
        environmentID = container.flexInt(.environmentID)
        redirect = container.flexString(.redirect).flatMap(DomainRedirect.init(rawValue:))
        dockerComposeDomains = container.flexString(.dockerComposeDomains).flatMap(Self.composeDomains(from:))
        healthCheck = try? HealthCheck(from: decoder)
    }

    /// Coolify stores `docker_compose_domains` as a JSON string, `{"web": {"domain": "https://…"}}`, and sends it
    /// as that string. Reading it as an object would let snake_case conversion rename services such as `my_app`.
    static func composeDomains(from text: String) -> [String: String]? {
        guard let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object.reduce(into: [:]) { domains, entry in
            if let fields = entry.value as? [String: Any] {
                domains[entry.key] = fields["domain"] as? String ?? ""
            } else if let domain = entry.value as? String {
                domains[entry.key] = domain
            }
        }
    }
}

extension Application {
    /// The address Coolify gives a pull request's preview, built the way Coolify builds it: the template with the
    /// first domain's host and the PR number filled in, under that domain's scheme and port.
    ///
    /// `nil` without a domain or template, or when the template has `{{random}}`, which Coolify fills once and the API
    /// does not return. A preview whose domain was edited by hand in Coolify lives elsewhere, which the API also hides.
    public func previewURL(pullRequest: Int) -> URL? {
        guard pullRequest > 0,
            let template = previewURLTemplate?.trimmingCharacters(in: .whitespacesAndNewlines), !template.isEmpty,
            !template.contains("{{random}}"),
            let first = fqdn?.split(separator: ",").first?.trimmingCharacters(in: .whitespaces),
            let domain = URLComponents(string: first), let scheme = domain.scheme, let host = domain.host,
            !host.isEmpty
        else { return nil }
        let name =
            template
            .replacingOccurrences(of: "{{domain}}", with: host)
            .replacingOccurrences(of: "{{pr_id}}", with: String(pullRequest))
        var components = URLComponents()
        components.scheme = scheme
        components.host = name
        components.port = domain.port
        return components.url
    }
}

import Foundation

/// A one-click service from Coolify's template catalog.
///
/// The catalog is a JSON object keyed by slug. Coolify creates a service from a template by that slug, so `slug` is
/// what `ServiceDraft.type` takes.
public struct ServiceTemplate: Sendable, Hashable, Identifiable {
    public var slug: String
    public var slogan: String
    /// Coolify's own label, unnormalized: the feed mixes cases, plurals, and comma-joined lists.
    public var category: String?
    public var tags: [String]
    /// A path such as `svgs/ghost.svg`, relative to the root of any Coolify instance.
    public var logo: String?
    public var documentation: URL?
    /// The port the main container listens on, when the template names one.
    public var port: String?
    /// The oldest Coolify version that can run the template.
    public var minimumVersion: String?
    public var updatedAt: String?
    /// The Docker Compose file, decoded from the feed's base64.
    public var compose: String

    public var id: String { slug }
    public var updatedAtDate: Date? { updatedAt.flatMap(CoolifyTimestamp.parse) }

    public init(
        slug: String,
        slogan: String = "",
        category: String? = nil,
        tags: [String] = [],
        logo: String? = nil,
        documentation: URL? = nil,
        port: String? = nil,
        minimumVersion: String? = nil,
        updatedAt: String? = nil,
        compose: String = ""
    ) {
        self.slug = slug
        self.slogan = slogan
        self.category = category
        self.tags = tags
        self.logo = logo
        self.documentation = documentation
        self.port = port
        self.minimumVersion = minimumVersion
        self.updatedAt = updatedAt
        self.compose = compose
    }

    /// The containers and variables the compose file declares.
    public var outline: ComposeOutline { ComposeOutline(compose) }
}

/// One template as the feed stores it, before it learns its slug.
struct ServiceTemplateEntry: Decodable {
    var slogan: String?
    var category: String?
    var tags: [String]?
    var logo: String?
    var documentation: String?
    var port: String?
    var minversion: String?
    var templateLastUpdatedAt: String?
    var compose: String?

    enum CodingKeys: String, CodingKey {
        case slogan
        case category
        case tags
        case logo
        case documentation
        case port
        case minversion
        case templateLastUpdatedAt = "template_last_updated_at"
        case compose
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slogan = container.flexString(.slogan)
        category = container.flexString(.category)
        tags = try? container.decodeIfPresent([String].self, forKey: .tags)
        logo = container.flexString(.logo)
        documentation = container.flexString(.documentation)
        port = container.flexString(.port)
        minversion = container.flexString(.minversion)
        templateLastUpdatedAt = container.flexString(.templateLastUpdatedAt)
        compose = container.flexString(.compose)
    }

    func template(slug: String) -> ServiceTemplate {
        let decoded = compose.flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
        return ServiceTemplate(
            slug: slug,
            slogan: slogan ?? "",
            category: category.flatMap { $0.isEmpty ? nil : $0 },
            tags: tags ?? [],
            logo: logo.flatMap { $0.isEmpty ? nil : $0 },
            documentation: documentation.flatMap(URL.init(string:)),
            port: port.flatMap { $0.isEmpty ? nil : $0 },
            minimumVersion: minversion,
            updatedAt: templateLastUpdatedAt,
            compose: decoded.map { String(decoding: $0, as: UTF8.self) } ?? ""
        )
    }
}

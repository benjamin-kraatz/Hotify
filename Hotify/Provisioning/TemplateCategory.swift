import CoolifyAPI
import Foundation

/// A shelf in the template gallery.
///
/// Coolify's feed spells categories many ways, such as `databases`, `Mail`, and `database,observability,developer-tools`.
/// Each template lands on one shelf here, by the first label that maps to one.
enum TemplateCategory: String, CaseIterable, Identifiable, Hashable {
    case ai
    case automation
    case analytics
    case monitoring
    case cms
    case productivity
    case development
    case git
    case backend
    case database
    case storage
    case media
    case messaging
    case email
    case auth
    case security
    case networking
    case search
    case finance
    case games
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .ai: "AI"
        case .automation: "Automation"
        case .analytics: "Analytics"
        case .monitoring: "Monitoring"
        case .cms: "Publishing"
        case .productivity: "Productivity"
        case .development: "Developer Tools"
        case .git: "Git"
        case .backend: "Backends"
        case .database: "Databases"
        case .storage: "Storage"
        case .media: "Media"
        case .messaging: "Chat"
        case .email: "Email"
        case .auth: "Sign-in"
        case .security: "Security"
        case .networking: "Networking"
        case .search: "Search"
        case .finance: "Finance"
        case .games: "Games"
        case .other: "Everything Else"
        }
    }

    var systemImage: String {
        switch self {
        case .ai: "sparkles"
        case .automation: "gearshape.2"
        case .analytics: "chart.bar.xaxis"
        case .monitoring: "waveform.path.ecg"
        case .cms: "doc.richtext"
        case .productivity: "checklist"
        case .development: "hammer"
        case .git: "arrow.triangle.branch"
        case .backend: "server.rack"
        case .database: "cylinder.split.1x2"
        case .storage: "externaldrive"
        case .media: "play.rectangle"
        case .messaging: "bubble.left.and.bubble.right"
        case .email: "envelope"
        case .auth: "person.badge.key"
        case .security: "lock.shield"
        case .networking: "network"
        case .search: "magnifyingglass"
        case .finance: "banknote"
        case .games: "gamecontroller"
        case .other: "square.grid.2x2"
        }
    }

    init(_ template: ServiceTemplate) {
        let labels = (template.category ?? "").lowercased().split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        self = labels.lazy.compactMap(Self.shelf(for:)).first ?? .other
    }

    private nonisolated static func shelf(for label: String) -> TemplateCategory? {
        switch label {
        case "ai", "mcp": .ai
        case "automation", "ci": .automation
        case "analytics": .analytics
        case "monitoring", "observability", "health": .monitoring
        case "cms", "documentation", "rss": .cms
        case "productivity", "helpdesk", "family": .productivity
        case "devtools", "developer-tools", "development", "api": .development
        case "git": .git
        case "backend": .backend
        case "database", "databases": .database
        case "storage": .storage
        case "media": .media
        case "messaging", "communication": .messaging
        case "email", "mail": .email
        case "auth": .auth
        case "security", "vpn": .security
        case "networking", "proxy": .networking
        case "search": .search
        case "finance": .finance
        case "games": .games
        default: nil
        }
    }

    /// Well-known templates for the opening shelf, in the order they show. Ones the feed lacks are skipped.
    static let popular = [
        "n8n", "ghost", "uptime-kuma", "umami", "supabase", "open-webui", "vaultwarden", "nextcloud", "immich",
        "pocketbase", "directus", "forgejo", "grafana", "metabase", "listmonk", "excalidraw",
    ]
}

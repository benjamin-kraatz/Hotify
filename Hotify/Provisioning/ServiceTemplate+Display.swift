import CoolifyAPI
import Foundation

extension ServiceTemplate {
    /// The slug as a name: `gitea-with-postgresql` reads `Gitea with PostgreSQL`.
    var displayName: String {
        slug.split(separator: "-").enumerated().map { index, word in
            let lower = word.lowercased()
            if let known = Self.spellings[lower] { return known }
            if index > 0, lower == "with" || lower == "and" { return lower }
            // Names like n8n or k3s keep the case they were written in.
            if word.contains(where: \.isNumber) { return String(word) }
            return word.prefix(1).uppercased() + word.dropFirst()
        }
        .joined(separator: " ")
    }

    var shelf: TemplateCategory { TemplateCategory(self) }

    /// Every instance serves the template logos itself, so they load from the instance and not a third party.
    func logoURL(instanceRoot: URL?) -> URL? {
        guard let logo, let instanceRoot else { return nil }
        return instanceRoot.appending(path: logo)
    }

    /// How well the template answers a search, or `nil` when it does not. A name match outranks a tag or the slogan.
    func searchScore(_ query: String) -> Int? {
        let name = displayName
        if name.localizedStandardRange(of: query)?.lowerBound == name.startIndex || slug.hasPrefix(query.lowercased()) {
            return 0
        }
        if name.localizedStandardContains(query) { return 1 }
        if tags.contains(where: { $0.localizedStandardContains(query) }) || shelf.title.localizedStandardContains(query)
        {
            return 2
        }
        if slogan.localizedStandardContains(query) { return 3 }
        return nil
    }

    private static let spellings: [String: String] = [
        "ai": "AI", "api": "API", "ui": "UI", "webui": "WebUI", "pdf": "PDF", "mysql": "MySQL",
        "postgresql": "PostgreSQL", "mariadb": "MariaDB", "mongodb": "MongoDB", "clickhouse": "ClickHouse",
        "pocketbase": "PocketBase", "denokv": "Deno KV", "minio": "MinIO", "vpn": "VPN", "smtp": "SMTP",
        "llm": "LLM", "rss": "RSS", "cms": "CMS", "s3": "S3", "sqlite": "SQLite", "phpmyadmin": "phpMyAdmin",
        "wordpress": "WordPress", "nocodb": "NocoDB", "pgadmin": "pgAdmin", "openobserve": "OpenObserve",
        "uptime": "Uptime", "kuma": "Kuma", "github": "GitHub", "gitlab": "GitLab", "redis": "Redis",
    ]
}

import CoolifyAPI
import Foundation

/// One application, database, or service, cut down to the plain values the list and detail header show.
struct ResourceSummary: Identifiable, Hashable {
    var route: ResourceRoute
    var name: String
    var status: String?
    var subtitle: String?
    var link: URL?
    var containers: [ContainerSummary] = []
    var place: ResourcePlace?
    /// An application with a production deployment queued or building, whoever started it.
    var isDeploying = false
    /// The deployment to cancel while `isDeploying` is true.
    var activeDeploymentID: String?

    var id: ResourceRoute { route }
    var kind: ResourceKind { route.kind }
    var heat: Heat { Heat(status: status) }

    /// Warming while an action or a deployment runs, so every screen agrees on the flame.
    func heat(pendingAction: ResourceAction?) -> Heat {
        pendingAction == nil && !isDeploying ? heat : .warming
    }
}

/// One container inside a service.
struct ContainerSummary: Identifiable, Hashable {
    var id: Int
    var name: String
    /// The Coolify `name` that service log requests use. `name` above may be the friendlier `humanName`.
    var serviceName = ""
    var status: String?
    var image: String?
    var link: URL?

    var heat: Heat { Heat(status: status) }
}

extension ResourceSummary {
    init(application: Application, place: ResourcePlace? = nil, activeDeployment: Deployment? = nil) {
        let link = Self.firstURL(in: application.fqdn)
        self.init(
            route: .application(application.uuid),
            name: application.name.isEmpty ? application.uuid : application.name,
            status: application.status,
            subtitle: link?.host() ?? Self.repositoryName(application.gitRepository),
            link: link,
            place: place,
            isDeploying: activeDeployment != nil,
            activeDeploymentID: activeDeployment.flatMap { $0.deploymentUUID.isEmpty ? nil : $0.deploymentUUID }
        )
    }

    init(database: Database, place: ResourcePlace? = nil) {
        let name = database.name ?? ""
        self.init(
            route: .database(database.uuid),
            name: name.isEmpty ? database.uuid : name,
            status: database.status,
            subtitle: Self.engineName(database.databaseType),
            place: place
        )
    }

    init(service: Service, place: ResourcePlace? = nil) {
        let containers = (service.applications ?? []).map { container in
            ContainerSummary(
                id: container.id,
                name: container.humanName ?? container.name,
                serviceName: container.name,
                status: container.status,
                image: container.image,
                link: Self.firstURL(in: container.fqdn)
            )
        }
        let count = containers.count
        self.init(
            route: .service(service.uuid),
            name: service.serviceType ?? service.name,
            status: service.status,
            subtitle: count == 1 ? "1 container" : "\(count) containers",
            link: containers.lazy.compactMap(\.link).first,
            containers: containers,
            place: place
        )
    }

    /// Turns `standalone-postgresql` into `PostgreSQL`.
    private static func engineName(_ type: String?) -> String? {
        guard let type, !type.isEmpty else { return nil }
        let engine = type.hasPrefix("standalone-") ? String(type.dropFirst("standalone-".count)) : type
        let names = [
            "postgresql": "PostgreSQL",
            "mysql": "MySQL",
            "mariadb": "MariaDB",
            "mongodb": "MongoDB",
            "redis": "Redis",
            "keydb": "KeyDB",
            "dragonfly": "Dragonfly",
            "clickhouse": "ClickHouse",
        ]
        return names[engine] ?? engine.capitalized
    }

    /// Coolify joins several domains with commas in one `fqdn` string.
    private static func firstURL(in fqdn: String?) -> URL? {
        guard let first = fqdn?.split(separator: ",").first else { return nil }
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    /// Turns `git@github.com:owner/repo.git` or an https remote into `owner/repo`.
    private static func repositoryName(_ remote: String?) -> String? {
        guard let remote, !remote.isEmpty else { return nil }
        var path = remote
        if let colon = path.lastIndex(of: ":"), !path.contains("://") {
            path = String(path[path.index(after: colon)...])
        } else if let url = URL(string: remote), url.host() != nil {
            path = String(url.path().drop { $0 == "/" })
        }
        if path.hasSuffix(".git") {
            path.removeLast(4)
        }
        return path.isEmpty ? remote : path
    }
}

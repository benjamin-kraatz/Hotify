import CoolifyAPI
import Foundation

extension DatabaseEngine {
    var displayName: String {
        switch self {
        case .postgresql: "PostgreSQL"
        case .mysql: "MySQL"
        case .mariadb: "MariaDB"
        case .mongodb: "MongoDB"
        case .redis: "Redis"
        case .keydb: "KeyDB"
        case .dragonfly: "Dragonfly"
        case .clickhouse: "ClickHouse"
        }
    }

    var slogan: String {
        switch self {
        case .postgresql: "The relational database most apps expect."
        case .mysql: "The relational database of countless web apps."
        case .mariadb: "MySQL's open fork, a drop-in replacement."
        case .mongodb: "Documents instead of tables."
        case .redis: "An in-memory store for caches, queues, and sessions."
        case .keydb: "A multithreaded Redis, compatible with its clients."
        case .dragonfly: "A Redis replacement built for many cores."
        case .clickhouse: "A column store for analytics on large data."
        }
    }

    /// The port it listens on, which a public port usually mirrors.
    var port: Int {
        switch self {
        case .postgresql: 5432
        case .mysql, .mariadb: 3306
        case .mongodb: 27017
        case .redis, .keydb, .dragonfly: 6379
        case .clickhouse: 9000
        }
    }

    /// Every Coolify instance serves its engines' logos under `/svgs`.
    func logoURL(instanceRoot: URL?) -> URL? {
        instanceRoot?.appending(path: "svgs/\(rawValue).svg")
    }
}

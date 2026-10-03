import Foundation

/// A database Coolify can create on its own, outside a service. The raw value is the path Coolify creates it under.
public enum DatabaseEngine: String, CaseIterable, Sendable, Hashable, Identifiable {
    case postgresql
    case mysql
    case mariadb
    case mongodb
    case redis
    case keydb
    case dragonfly
    case clickhouse

    public var id: String { rawValue }
}

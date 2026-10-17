import Foundation

/// An engine Coolify can import a backup into. Coolify 4.4 refuses imports for every other engine.
public enum DatabaseImportEngine: String, Sendable, Hashable, CaseIterable {
    case postgresql
    case mysql
    case mariadb
    case mongodb
    case sqlite

    /// Reads a standalone database's type, such as `standalone-postgresql`. `nil` when Coolify cannot import into it.
    public init?(databaseType: String?) {
        guard let type = databaseType?.lowercased(), !type.isEmpty else { return nil }
        self.init(matching: type)
    }

    /// Reads a service database container's engine the way Coolify does: from its custom type when it has one, else
    /// from the image name before the first `:`.
    public init?(serviceImage: String?, customType: String? = nil) {
        if let customType = customType?.trimmingCharacters(in: .whitespaces).lowercased(), !customType.isEmpty {
            self.init(matching: customType)
            return
        }
        guard let image = serviceImage?.lowercased(), !image.isEmpty else { return nil }
        let name = image.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
        guard let name, !name.isEmpty else { return nil }
        // Coolify counts these PostgreSQL images as PostgreSQL even though some names do not contain "postgres".
        if name.contains("timescale") || name.contains("pgvector") || name.contains("postgis") {
            self = .postgresql
            return
        }
        self.init(matching: name)
    }

    /// Coolify's import matches on substrings, and checks MariaDB before MySQL.
    private init?(matching type: String) {
        if type.contains("postgres") {
            self = .postgresql
        } else if type.contains("mariadb") {
            self = .mariadb
        } else if type.contains("mysql") {
            self = .mysql
        } else if type.contains("mongo") {
            self = .mongodb
        } else if type.contains("sqlite") {
            self = .sqlite
        } else {
            return nil
        }
    }
}

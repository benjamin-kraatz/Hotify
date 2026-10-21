import Foundation

/// The database an import writes into: a standalone database, or a database container inside a service.
public enum DatabaseImportTarget: Sendable, Hashable {
    case database(String)
    case serviceDatabase(service: String, database: String)

    /// The encoded path up to and including `imports`.
    var importsPath: String {
        switch self {
        case .database(let uuid):
            "databases/\(CoolifyURL.encodePathComponent(uuid))/imports"
        case .serviceDatabase(let service, let database):
            "services/\(CoolifyURL.encodePathComponent(service))/databases/"
                + "\(CoolifyURL.encodePathComponent(database))/imports"
        }
    }
}

/// Where Coolify reads the backup from.
public enum DatabaseImportSource: Sendable, Hashable {
    /// A finished upload, by the id it was uploaded with.
    case upload(String)
    /// An absolute path on the database's server. Coolify requires a token with the `deploy` ability for this.
    case server(path: String)
    /// An object in one of the team's S3 stores. `storage` is the store's uuid, or its numeric id.
    case s3(storage: String, path: String)
}

/// How Coolify restores the backup. Each flag only applies to some engines, and Coolify ignores it for the rest.
public struct DatabaseImportOptions: Sendable, Hashable {
    /// PostgreSQL, MySQL, and MariaDB: the backup holds every database, and every existing database is dropped first.
    public var dumpAll: Bool
    /// PostgreSQL single-database restores replace matching objects. MongoDB drops each restored collection first.
    public var replaceExisting: Bool
    /// PostgreSQL archives: restore owners and privileges, which are skipped by default.
    public var keepOwners: Bool
    /// MySQL and MariaDB with `dumpAll`: also restore users, passwords, and privileges.
    public var restoreMySQLUsers: Bool
    /// SQLite: the database file to restore into. Coolify picks one when this is `nil`.
    public var sqliteDatabase: String?

    public init(
        dumpAll: Bool = false,
        replaceExisting: Bool = false,
        keepOwners: Bool = false,
        restoreMySQLUsers: Bool = false,
        sqliteDatabase: String? = nil
    ) {
        self.dumpAll = dumpAll
        self.replaceExisting = replaceExisting
        self.keepOwners = keepOwners
        self.restoreMySQLUsers = restoreMySQLUsers
        self.sqliteDatabase = sqliteDatabase
    }
}

/// The body of `POST …/imports`. Coolify answers 422 for a key it does not expect, so only the source's own keys and
/// the flags that are on are sent.
struct DatabaseImportRequest: Encodable {
    var source: DatabaseImportSource
    var options: DatabaseImportOptions

    private enum CodingKeys: String, CodingKey {
        case source
        case uploadID = "upload_id"
        case s3StorageUUID = "s3_storage_uuid"
        case path
        case dumpAll = "dump_all"
        case replaceExisting = "replace_existing"
        case keepOwners = "keep_owners"
        case restoreMySQLUsers = "restore_mysql_users"
        case sqliteDatabase = "sqlite_database"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch source {
        case .upload(let id):
            try container.encode("upload", forKey: .source)
            try container.encode(id, forKey: .uploadID)
        case .server(let path):
            try container.encode("server", forKey: .source)
            try container.encode(path, forKey: .path)
        case .s3(let storage, let path):
            try container.encode("s3", forKey: .source)
            try container.encode(storage, forKey: .s3StorageUUID)
            try container.encode(path, forKey: .path)
        }
        if options.dumpAll { try container.encode(true, forKey: .dumpAll) }
        if options.replaceExisting { try container.encode(true, forKey: .replaceExisting) }
        if options.keepOwners { try container.encode(true, forKey: .keepOwners) }
        if options.restoreMySQLUsers { try container.encode(true, forKey: .restoreMySQLUsers) }
        if let file = options.sqliteDatabase?.trimmingCharacters(in: .whitespaces), !file.isEmpty {
            try container.encode(file, forKey: .sqliteDatabase)
        }
    }
}

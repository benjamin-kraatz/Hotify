import CoolifyAPI
import Foundation

extension DatabaseImportEngine {
    var displayName: String {
        switch self {
        case .postgresql: "PostgreSQL"
        case .mysql: "MySQL"
        case .mariadb: "MariaDB"
        case .mongodb: "MongoDB"
        case .sqlite: "SQLite"
        }
    }

    /// The backups Coolify's import reads for this engine, as a hint under the file picker.
    var acceptedFormats: String {
        switch self {
        case .postgresql:
            "A pg_dump archive in custom or tar format, or an SQL dump, such as .dmp, .dump, .tar, .sql, or .sql.gz."
        case .mysql, .mariadb:
            "An SQL dump, such as .sql, .sql.gz, or .dmp, or a tar that holds exactly one."
        case .mongodb:
            "A mongodump archive, plain or gzip, or a dump directory packed as .tar or .tar.gz. A single .bson file "
                + "doesn't work."
        case .sqlite:
            "A SQLite database file, such as .db, .sqlite, or .sqlite3, plain or gzip."
        }
    }

    /// Whether a backup can hold every database of the server, which needs `dump_all`.
    var offersDumpAll: Bool {
        switch self {
        case .postgresql, .mysql, .mariadb: true
        case .mongodb, .sqlite: false
        }
    }

    /// Every engine Coolify imports into, for the screen that says this one is not among them.
    static var supportedList: String {
        let names = allCases.map(\.displayName)
        return names.dropLast().joined(separator: ", ") + ", and " + (names.last ?? "")
    }
}

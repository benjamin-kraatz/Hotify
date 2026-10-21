import CoolifyAPI
import Foundation

/// What a PostgreSQL backup most likely holds, read from its file name.
///
/// Coolify looks at the content, not the name, so this only picks which explanation to show and whether the owners
/// switch applies. `unknown` shows both.
enum BackupFormat: Hashable {
    /// A pg_dump archive in custom or tar format, which pg_restore reads.
    case archive
    /// Plain SQL, which psql reads.
    case sql
    case unknown

    init(filename: String?) {
        guard let filename, let ext = DatabaseImportFile.allowedExtension(for: filename) else {
            self = .unknown
            return
        }
        switch ext {
        // Coolify writes a single PostgreSQL database as a custom-format `.dmp`.
        case "dmp", "dump", "tar":
            self = .archive
        case "sql", "sql.gz":
            self = .sql
        default:
            self = .unknown
        }
    }
}

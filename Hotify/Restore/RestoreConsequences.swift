import CoolifyAPI
import Foundation

/// What a restore does to the data already in the database, for one engine and its options. Says no more than
/// Coolify's import commands do.
struct RestoreConsequences {
    var engine: DatabaseImportEngine
    var options: DatabaseImportOptions
    var format: BackupFormat

    /// Something already in the database gets dropped or overwritten, which the confirmation names.
    var replacesData: Bool {
        switch engine {
        case .postgresql: options.dumpAll || options.replaceExisting
        case .mysql, .mariadb, .sqlite: true
        case .mongodb: options.replaceExisting
        }
    }

    var lines: [String] {
        switch engine {
        case .postgresql: postgresql
        case .mysql, .mariadb: mysql
        case .mongodb: mongodb
        case .sqlite: sqlite
        }
    }

    /// The first line, which the confirmation repeats.
    var headline: String {
        lines.first ?? ""
    }

    private var postgresql: [String] {
        if options.dumpAll {
            return [
                "Coolify ends every connection, drops every database on this PostgreSQL server, recreates the "
                    + "default one, and then restores the backup.",
                "This is not one transaction. If it fails part way, the server is left partly restored.",
            ]
        }
        var lines: [String]
        if options.replaceExisting {
            let archive =
                "Coolify drops each object the backup holds, then restores it, all in one transaction. "
                + "If anything fails, it rolls back and your current data stays."
            let sql =
                "Coolify restores into a new database and swaps it in for the current one only if the restore "
                + "succeeds. Open connections are ended, and data the backup doesn't hold is gone after the swap."
            switch format {
            case .archive: lines = [archive]
            case .sql: lines = [sql]
            case .unknown: lines = ["For a pg_dump archive: " + archive, "For an SQL dump: " + sql]
            }
        } else {
            lines = [
                "Coolify restores into the database Coolify set up for it, in one transaction. If the backup holds an "
                    + "object that already exists, the import fails and rolls back, so your current data stays."
            ]
        }
        if format != .sql {
            lines.append(
                options.keepOwners
                    ? "Owners and privileges come from the backup. The roles they name have to exist on this server."
                    : "Owners and privileges in the backup are skipped, so the database's own user owns what it "
                        + "restores.")
        }
        return lines
    }

    private var mysql: [String] {
        let notTransactional = "This is not one transaction. If it fails part way, some of it is already replaced."
        guard options.dumpAll else {
            return [
                "Coolify runs the dump against the database Coolify set up for it. A mysqldump dump drops and "
                    + "recreates each table it holds. Tables the dump doesn't name stay.",
                notTransactional,
            ]
        }
        return [
            "Coolify ends other connections, drops every database except the system ones, and then restores the "
                + "backup.",
            options.restoreMySQLUsers
                ? "Users, passwords, and privileges come from the backup too. The credentials Coolify keeps for this "
                    + "database can stop working."
                : "Users, passwords, and privileges stay as they are. The backup's system databases are skipped.",
            notTransactional,
        ]
    }

    private var mongodb: [String] {
        options.replaceExisting
            ? [
                "Coolify drops each collection the backup holds, then restores it. Collections the backup doesn't "
                    + "hold stay."
            ]
            : [
                "Coolify adds the backup's documents. Documents that already exist stay, and their duplicates in "
                    + "the backup are skipped."
            ]
    }

    private var sqlite: [String] {
        let file =
            options.sqliteDatabase.map { "\($0)" }
            ?? "the database file the backup's name points to, or else the first one"
        return ["Coolify replaces the whole contents of \(file) with the backup."]
    }
}

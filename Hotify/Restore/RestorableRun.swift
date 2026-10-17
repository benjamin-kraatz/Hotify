import CoolifyAPI
import Foundation

/// A successful backup run whose dump Coolify still keeps somewhere it can import from.
struct RestorableRun: Identifiable, Hashable {
    var id: String
    var date: Date?
    var size: Int?
    var databaseName: String?
    var filename: String?
    var sources: StoredBackupSources
    /// The schedule dumped every database, so the restore has to replace them all.
    var dumpAll: Bool

    init?(execution: BackupExecution, backup: DatabaseBackup) {
        guard execution.isSuccessful else { return nil }
        let sources = StoredBackupSources(execution: execution, backup: backup)
        guard !sources.isEmpty else { return nil }
        id = execution.id
        date = execution.createdAtDate
        size = execution.size
        databaseName = execution.databaseName ?? backup.databasesToBackup
        filename = execution.filename
        self.sources = sources
        dumpAll = backup.dumpAll
    }

    /// Every restorable run of every schedule, newest first.
    static func all(in backups: [DatabaseBackup]) -> [RestorableRun] {
        backups
            .flatMap { backup in backup.executions.compactMap { RestorableRun(execution: $0, backup: backup) } }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    var fileName: String? {
        filename.map { ($0 as NSString).lastPathComponent }
    }

    /// The run's date and size, such as `Sep 29, 2026 at 4:00 AM · 48.2 MB`.
    var title: String {
        var parts: [String] = []
        if let date {
            parts.append(date.formatted(date: .abbreviated, time: .shortened))
        }
        if let size, size > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        return parts.isEmpty ? (fileName ?? "Backup run") : parts.joined(separator: " · ")
    }
}

import CoolifyAPI
import Foundation

/// Loads backup history and tracks explicit execution requests without retrying writes.
@Observable
final class BackupsModel {
    var backups: [DatabaseBackup] = []
    var error: String?
    var notice: String?
    var hasLoaded = false
    var isLoading = false
    var sending: String?
    var requested: [String: Date] = [:]

    func refresh(client: CoolifyClient, database: String) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await client.databaseBackups(database)
            try Task.checkCancellation()
            backups = loaded
            hasLoaded = true
            error = nil
        } catch is CancellationError { return } catch {
            self.error = (error as? CoolifyError)?.message ?? error.localizedDescription
        }
    }

    func isBusy(_ backup: DatabaseBackup) -> Bool {
        sending == backup.id || requested[backup.id].map { Date.now.timeIntervalSince($0) < 60 } == true
            || backup.executions.contains { ["running", "in_progress", "queued"].contains($0.status) }
    }

    func run(_ backup: DatabaseBackup, client: CoolifyClient, database: String) async {
        guard !isBusy(backup) else { return }
        sending = backup.id
        defer { sending = nil }
        do {
            _ = try await client.backUpNow(database: database, backup: backup.id)
            requested[backup.id] = .now
            notice = "Backup requested. Its result will appear in the history when Coolify reports it."
            await refresh(client: client, database: database)
        } catch {
            // A lost response can follow an accepted write. Do not automatically send it again.
            self.error = "The backup request could not be confirmed. Check the history before trying again."
            requested[backup.id] = .now
        }
    }
}

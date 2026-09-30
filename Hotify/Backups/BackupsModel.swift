import CoolifyAPI
import Foundation

/// Loads backup history and tracks explicit execution requests without retrying writes.
@Observable
final class BackupsModel {
    var backups: [DatabaseBackup] = []
    var error: String?
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

    /// When a backup was asked for, until its execution shows up in the history or a minute passes.
    func pendingSince(_ backup: DatabaseBackup) -> Date? {
        guard let asked = requested[backup.id], Date.now.timeIntervalSince(asked) < 60 else { return nil }
        // A few seconds of slack, because the server's clock stamps the execution.
        let arrived = backup.executions.contains { ($0.createdAtDate ?? .distantPast) >= asked.addingTimeInterval(-5) }
        return arrived ? nil : asked
    }

    func isBusy(_ backup: DatabaseBackup) -> Bool {
        sending == backup.id || pendingSince(backup) != nil || backup.executions.contains(where: \.isUnderway)
    }

    func run(_ backup: DatabaseBackup, client: CoolifyClient, database: String) async {
        guard !isBusy(backup) else { return }
        sending = backup.id
        defer { sending = nil }
        do {
            _ = try await client.backUpNow(database: database, backup: backup.id)
            requested[backup.id] = .now
            error = nil
            await refresh(client: client, database: database)
        } catch {
            // A lost response can follow an accepted write. Do not automatically send it again.
            self.error = "The backup request could not be confirmed. Check the history before trying again."
            requested[backup.id] = .now
        }
    }
}

import Foundation

extension CoolifyClient {
    /// Lists existing backup configurations with their executions. Does not create a schedule.
    public func databaseBackups(_ uuid: String) async throws -> [DatabaseBackup] {
        try await getList("databases/\(CoolifyURL.encodePathComponent(uuid))/backups")
    }

    public func backupExecutions(database uuid: String, backup backupUUID: String) async throws -> [BackupExecution] {
        let response: Executions = try await get(
            "databases/\(CoolifyURL.encodePathComponent(uuid))/backups/\(CoolifyURL.encodePathComponent(backupUUID))/executions"
        )
        return response.executions
    }

    /// Queues a backup using an existing configuration without changing its schedule or retention.
    public func backUpNow(database uuid: String, backup backupUUID: String) async throws -> QueuedAction {
        // Coolify 4.3 uses the configuration PATCH endpoint for one-off execution too.
        try await patch(
            "databases/\(CoolifyURL.encodePathComponent(uuid))/backups/\(CoolifyURL.encodePathComponent(backupUUID))",
            body: RunBackup())
    }
}

private struct RunBackup: Encodable { let backupNow = true }
private struct Executions: Decodable { var executions: [BackupExecution] }

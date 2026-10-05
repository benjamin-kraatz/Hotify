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

    /// Creates a schedule. Fields left `nil` stay out of the JSON.
    ///
    /// Coolify 4.3 answers 422 for a key it does not expect, and requires `s3_storage_uuid` when `save_s3` is true.
    /// `frequency` is required.
    public func createDatabaseBackup(
        database uuid: String,
        _ draft: DatabaseBackupDraft
    ) async throws -> CreatedResource {
        try await post("databases/\(CoolifyURL.encodePathComponent(uuid))/backups", body: draft)
    }

    /// Changes a schedule. Fields left `nil` stay out of the JSON, and `backupNow` is sent only when it is set.
    public func updateDatabaseBackup(
        database uuid: String,
        backup backupUUID: String,
        _ draft: DatabaseBackupDraft
    ) async throws -> QueuedAction {
        try await patch(
            "databases/\(CoolifyURL.encodePathComponent(uuid))/backups/\(CoolifyURL.encodePathComponent(backupUUID))",
            body: draft
        )
    }

    /// Deletes the schedule and its execution history.
    ///
    /// Stored dumps stay unless `deleteS3` is true. The query is left off otherwise, which is Coolify's own default.
    public func deleteDatabaseBackup(
        database uuid: String,
        backup backupUUID: String,
        deleteS3: Bool = false
    ) async throws -> QueuedAction {
        let path =
            "databases/\(CoolifyURL.encodePathComponent(uuid))/backups/\(CoolifyURL.encodePathComponent(backupUUID))"
        if deleteS3 {
            return try await delete(path, query: [URLQueryItem(name: "delete_s3", value: Self.flag(true))])
        }
        return try await delete(path)
    }
}

private struct RunBackup: Encodable { let backupNow = true }
private struct Executions: Decodable { var executions: [BackupExecution] }

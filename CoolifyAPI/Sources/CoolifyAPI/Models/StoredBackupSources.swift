import Foundation

/// Where a successful backup run can be imported from: the dump on the database's server, its copy in S3, or both.
///
/// Coolify writes the dump to an absolute path on the server and uploads it to S3 under that same path, so one path
/// serves both sources.
public struct StoredBackupSources: Sendable, Hashable {
    public var server: DatabaseImportSource?
    public var s3: DatabaseImportSource?

    public var isEmpty: Bool { server == nil && s3 == nil }

    public init(server: DatabaseImportSource? = nil, s3: DatabaseImportSource? = nil) {
        self.server = server
        self.s3 = s3
    }

    public init(execution: BackupExecution, backup: DatabaseBackup) {
        guard execution.isSuccessful,
            let path = execution.filename?.trimmingCharacters(in: .whitespacesAndNewlines),
            path.hasPrefix("/")
        else {
            self.init()
            return
        }
        let server: DatabaseImportSource? = execution.localStorageDeleted == true ? nil : .server(path: path)
        // A run from before Coolify recorded `s3_uploaded` falls back to the schedule's own setting.
        let uploaded = execution.s3Uploaded ?? backup.saveS3
        var s3: DatabaseImportSource?
        if uploaded, execution.s3StorageDeleted != true, let storage = backup.s3StorageUUID ?? backup.s3StorageID {
            s3 = .s3(storage: storage, path: String(path.drop { $0 == "/" }))
        }
        self.init(server: server, s3: s3)
    }
}

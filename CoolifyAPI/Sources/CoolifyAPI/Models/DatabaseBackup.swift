import Foundation

/// An existing database backup configuration and its execution history.
public struct DatabaseBackup: Decodable, Sendable, Identifiable {
    public var uuid: String
    public var enabled: Bool
    public var frequency: String?
    public var databasesToBackup: String?
    public var dumpAll: Bool
    public var saveS3: Bool
    /// The store that receives a remote copy, when the response names one.
    public var s3StorageUUID: String?
    public var databaseBackupRetentionAmountLocally: Int?
    public var databaseBackupRetentionDaysLocally: Int?
    public var databaseBackupRetentionMaxStorageLocally: Double?
    public var databaseBackupRetentionAmountS3: Int?
    public var databaseBackupRetentionDaysS3: Int?
    public var databaseBackupRetentionMaxStorageS3: Double?
    public var timeout: Int?
    public var executions: [BackupExecution]
    public var id: String { uuid }

    enum CodingKeys: String, CodingKey {
        case uuid
        case enabled
        case frequency
        case databasesToBackup
        case executions
        case dumpAll
        case saveS3
        // `s3_storage_uuid` becomes `s3StorageUuid` after snake_case conversion.
        case s3StorageUuid
        case timeout
        case databaseBackupRetentionAmountLocally
        case databaseBackupRetentionDaysLocally
        case databaseBackupRetentionMaxStorageLocally
        case databaseBackupRetentionAmountS3
        case databaseBackupRetentionDaysS3
        case databaseBackupRetentionMaxStorageS3
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = container.flexString(.uuid) ?? ""
        enabled = container.flexBool(.enabled) ?? false
        frequency = container.flexString(.frequency)
        databasesToBackup = container.flexString(.databasesToBackup)
        dumpAll = container.flexBool(.dumpAll) ?? false
        saveS3 = container.flexBool(.saveS3) ?? false
        // Coolify 4.3.23 lists `s3_storage_id`, the numeric row, and not the uuid.
        // The uuid is kept when a response has it.
        s3StorageUUID = container.flexString(.s3StorageUuid)
        databaseBackupRetentionAmountLocally = container.flexInt(.databaseBackupRetentionAmountLocally)
        databaseBackupRetentionDaysLocally = container.flexInt(.databaseBackupRetentionDaysLocally)
        databaseBackupRetentionMaxStorageLocally = container.flexString(.databaseBackupRetentionMaxStorageLocally)
            .flatMap(Double.init)
        databaseBackupRetentionAmountS3 = container.flexInt(.databaseBackupRetentionAmountS3)
        databaseBackupRetentionDaysS3 = container.flexInt(.databaseBackupRetentionDaysS3)
        databaseBackupRetentionMaxStorageS3 = container.flexString(.databaseBackupRetentionMaxStorageS3).flatMap(
            Double.init)
        timeout = container.flexInt(.timeout)
        executions = try container.decodeIfPresent([BackupExecution].self, forKey: .executions) ?? []
    }
}

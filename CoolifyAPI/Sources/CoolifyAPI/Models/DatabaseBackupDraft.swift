import Foundation

/// The body that creates or changes a database backup schedule.
///
/// Nil fields stay out of the JSON. Coolify 4.3 answers 422 for a key it does not expect. On an update, `backupNow`
/// also runs the backup, so leave it nil unless that is the request. `backUpNow` sends that flag alone.
public struct DatabaseBackupDraft: Encodable, Sendable, Hashable {
    public var frequency: String?
    public var enabled: Bool?
    public var saveS3: Bool?
    /// Required by Coolify when `saveS3` is true.
    public var s3StorageUUID: String?
    public var databasesToBackup: String?
    public var dumpAll: Bool?
    public var backupNow: Bool?
    public var databaseBackupRetentionAmountLocally: Int?
    public var databaseBackupRetentionDaysLocally: Int?
    public var databaseBackupRetentionMaxStorageLocally: Double?
    public var databaseBackupRetentionAmountS3: Int?
    public var databaseBackupRetentionDaysS3: Int?
    public var databaseBackupRetentionMaxStorageS3: Double?
    public var timeout: Int?

    public init(
        frequency: String? = nil,
        enabled: Bool? = nil,
        saveS3: Bool? = nil,
        s3StorageUUID: String? = nil,
        databasesToBackup: String? = nil,
        dumpAll: Bool? = nil,
        backupNow: Bool? = nil,
        databaseBackupRetentionAmountLocally: Int? = nil,
        databaseBackupRetentionDaysLocally: Int? = nil,
        databaseBackupRetentionMaxStorageLocally: Double? = nil,
        databaseBackupRetentionAmountS3: Int? = nil,
        databaseBackupRetentionDaysS3: Int? = nil,
        databaseBackupRetentionMaxStorageS3: Double? = nil,
        timeout: Int? = nil
    ) {
        self.frequency = frequency
        self.enabled = enabled
        self.saveS3 = saveS3
        self.s3StorageUUID = s3StorageUUID
        self.databasesToBackup = databasesToBackup
        self.dumpAll = dumpAll
        self.backupNow = backupNow
        self.databaseBackupRetentionAmountLocally = databaseBackupRetentionAmountLocally
        self.databaseBackupRetentionDaysLocally = databaseBackupRetentionDaysLocally
        self.databaseBackupRetentionMaxStorageLocally = databaseBackupRetentionMaxStorageLocally
        self.databaseBackupRetentionAmountS3 = databaseBackupRetentionAmountS3
        self.databaseBackupRetentionDaysS3 = databaseBackupRetentionDaysS3
        self.databaseBackupRetentionMaxStorageS3 = databaseBackupRetentionMaxStorageS3
        self.timeout = timeout
    }

    public var isEmpty: Bool {
        frequency == nil && enabled == nil && saveS3 == nil && s3StorageUUID == nil && databasesToBackup == nil
            && dumpAll == nil && backupNow == nil && databaseBackupRetentionAmountLocally == nil
            && databaseBackupRetentionDaysLocally == nil && databaseBackupRetentionMaxStorageLocally == nil
            && databaseBackupRetentionAmountS3 == nil && databaseBackupRetentionDaysS3 == nil
            && databaseBackupRetentionMaxStorageS3 == nil && timeout == nil
    }

    enum CodingKeys: String, CodingKey {
        case frequency
        case enabled
        case saveS3
        // snake_case conversion of `s3StorageUUID` would split the acronym into `s3_storage_u_u_i_d`.
        case s3StorageUUID = "s3StorageUuid"
        case databasesToBackup
        case dumpAll
        case backupNow
        case databaseBackupRetentionAmountLocally
        case databaseBackupRetentionDaysLocally
        case databaseBackupRetentionMaxStorageLocally
        case databaseBackupRetentionAmountS3
        case databaseBackupRetentionDaysS3
        case databaseBackupRetentionMaxStorageS3
        case timeout
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(frequency, forKey: .frequency)
        try container.encodeIfPresent(enabled, forKey: .enabled)
        try container.encodeIfPresent(saveS3, forKey: .saveS3)
        try container.encodeIfPresent(s3StorageUUID, forKey: .s3StorageUUID)
        try container.encodeIfPresent(databasesToBackup, forKey: .databasesToBackup)
        try container.encodeIfPresent(dumpAll, forKey: .dumpAll)
        try container.encodeIfPresent(backupNow, forKey: .backupNow)
        try container.encodeIfPresent(
            databaseBackupRetentionAmountLocally, forKey: .databaseBackupRetentionAmountLocally)
        try container.encodeIfPresent(
            databaseBackupRetentionDaysLocally, forKey: .databaseBackupRetentionDaysLocally)
        try container.encodeIfPresent(
            databaseBackupRetentionMaxStorageLocally, forKey: .databaseBackupRetentionMaxStorageLocally)
        try container.encodeIfPresent(databaseBackupRetentionAmountS3, forKey: .databaseBackupRetentionAmountS3)
        try container.encodeIfPresent(databaseBackupRetentionDaysS3, forKey: .databaseBackupRetentionDaysS3)
        try container.encodeIfPresent(
            databaseBackupRetentionMaxStorageS3, forKey: .databaseBackupRetentionMaxStorageS3)
        try container.encodeIfPresent(timeout, forKey: .timeout)
    }
}

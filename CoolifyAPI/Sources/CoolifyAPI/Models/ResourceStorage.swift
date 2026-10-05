import Foundation

/// Whether a mount is a Docker volume or a file Coolify writes into the container.
public enum ResourceStorageKind: String, Codable, Sendable, Hashable {
    case persistent
    case file
}

/// A persistent volume or a file mount on an application, database, or service.
///
/// Coolify's list items are loosely specified. Unknown keys are ignored. A bool may arrive as `0` or `1`.
public struct ResourceStorage: Decodable, Sendable, Hashable, Identifiable {
    public var uuid: String
    public var kind: ResourceStorageKind
    public var name: String?
    public var mountPath: String
    public var content: String?
    public var isDirectory: Bool
    public var fsPath: String?
    /// A backup schedule nested on the storage, when the list includes one. There is no documented GET for it.
    public var backup: VolumeBackupSchedule?

    public var id: String { uuid }

    /// A volume, or a file mount that is a directory, can take a volume backup schedule.
    public var canScheduleBackup: Bool {
        kind == .persistent || (kind == .file && isDirectory)
    }

    public init(
        uuid: String,
        kind: ResourceStorageKind,
        name: String? = nil,
        mountPath: String,
        content: String? = nil,
        isDirectory: Bool = false,
        fsPath: String? = nil,
        backup: VolumeBackupSchedule? = nil
    ) {
        self.uuid = uuid
        self.kind = kind
        self.name = name
        self.mountPath = mountPath
        self.content = content
        self.isDirectory = isDirectory
        self.fsPath = fsPath
        self.backup = backup
    }

    enum CodingKeys: String, CodingKey {
        case uuid
        case type
        case name
        case mountPath
        case content
        case isDirectory
        case fsPath
        case backup
        case volumeBackup
        case scheduledBackup
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = container.flexString(.uuid) ?? ""
        let explicitKind = container.flexString(.type).flatMap(ResourceStorageKind.init(rawValue:))
        if let explicitKind {
            kind = explicitKind
        } else if container.flexBool(.isDirectory) == true || container.flexString(.fsPath) != nil {
            kind = .file
        } else {
            kind = .persistent
        }
        name = container.flexString(.name)
        mountPath = container.flexString(.mountPath) ?? ""
        content = container.flexString(.content)
        isDirectory = container.flexBool(.isDirectory) ?? false
        fsPath = container.flexString(.fsPath)
        backup = Self.nestedBackup(in: container)
    }

    /// The list groups items into two arrays that do not repeat `type`. The array wins over a missing or odd type.
    func withKind(_ kind: ResourceStorageKind) -> ResourceStorage {
        var copy = self
        copy.kind = kind
        return copy
    }

    private static func nestedBackup(in container: KeyedDecodingContainer<CodingKeys>) -> VolumeBackupSchedule? {
        for key in [CodingKeys.backup, .volumeBackup, .scheduledBackup] {
            let schedule: VolumeBackupSchedule?
            do {
                schedule = try container.decodeIfPresent(VolumeBackupSchedule.self, forKey: key)
            } catch {
                continue
            }
            guard let schedule, !schedule.frequency.isEmpty || !schedule.uuid.isEmpty else { continue }
            return schedule
        }
        return nil
    }
}

/// The body for creating or updating a mount.
///
/// Nil optionals stay out of the JSON. Coolify 4.3 answers 422 to a key it does not expect. A file create may send
/// `content`, `is_directory`, and `fs_path`. An update does not list `is_directory` or `fs_path`, so those stay out
/// once `uuid` is set. A persistent mount sends `name` and never the file keys.
public struct ResourceStorageDraft: Encodable, Sendable, Hashable {
    public var uuid: String?
    public var type: ResourceStorageKind
    public var name: String?
    public var mountPath: String
    public var content: String?
    public var isDirectory: Bool?
    public var fsPath: String?

    public init(
        uuid: String? = nil,
        type: ResourceStorageKind,
        name: String? = nil,
        mountPath: String,
        content: String? = nil,
        isDirectory: Bool? = nil,
        fsPath: String? = nil
    ) {
        self.uuid = uuid
        self.type = type
        self.name = name
        self.mountPath = mountPath
        self.content = content
        self.isDirectory = isDirectory
        self.fsPath = fsPath
    }

    enum CodingKeys: String, CodingKey {
        case uuid
        case type
        case name
        case mountPath
        case content
        case isDirectory
        case fsPath
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(uuid, forKey: .uuid)
        try container.encode(type, forKey: .type)
        try container.encode(mountPath, forKey: .mountPath)
        if type == .persistent {
            try container.encodeIfPresent(name?.nonEmpty, forKey: .name)
        }
        guard type == .file else { return }
        try container.encodeIfPresent(content, forKey: .content)
        // Coolify's update schema has no directory fields, and rejects unexpected keys.
        guard uuid == nil else { return }
        try container.encodeIfPresent(isDirectory, forKey: .isDirectory)
        try container.encodeIfPresent(fsPath?.nonEmpty, forKey: .fsPath)
    }
}

/// A volume backup schedule returned by PUT, or nested on a storage.
///
/// `storageType` is `persistent` or `directory`. There is no documented GET for this schedule.
public struct VolumeBackupSchedule: Decodable, Sendable, Hashable, Identifiable {
    public var uuid: String
    public var message: String?
    public var storageUuid: String?
    public var storageType: String?
    public var frequency: String
    public var enabled: Bool
    public var saveS3: Bool
    public var disableLocalBackup: Bool
    public var stopDuringBackup: Bool
    public var s3StorageUuid: String?
    public var retentionAmountLocally: Int?
    public var retentionDaysLocally: Int?
    public var retentionMaxStorageLocally: Double?
    public var retentionAmountS3: Int?
    public var retentionDaysS3: Int?
    public var retentionMaxStorageS3: Double?
    public var timeout: Int?

    public var id: String { uuid.isEmpty ? (storageUuid ?? frequency) : uuid }

    public init(
        uuid: String,
        message: String? = nil,
        storageUuid: String? = nil,
        storageType: String? = nil,
        frequency: String,
        enabled: Bool = true,
        saveS3: Bool = false,
        disableLocalBackup: Bool = false,
        stopDuringBackup: Bool = false,
        s3StorageUuid: String? = nil,
        retentionAmountLocally: Int? = nil,
        retentionDaysLocally: Int? = nil,
        retentionMaxStorageLocally: Double? = nil,
        retentionAmountS3: Int? = nil,
        retentionDaysS3: Int? = nil,
        retentionMaxStorageS3: Double? = nil,
        timeout: Int? = nil
    ) {
        self.uuid = uuid
        self.message = message
        self.storageUuid = storageUuid
        self.storageType = storageType
        self.frequency = frequency
        self.enabled = enabled
        self.saveS3 = saveS3
        self.disableLocalBackup = disableLocalBackup
        self.stopDuringBackup = stopDuringBackup
        self.s3StorageUuid = s3StorageUuid
        self.retentionAmountLocally = retentionAmountLocally
        self.retentionDaysLocally = retentionDaysLocally
        self.retentionMaxStorageLocally = retentionMaxStorageLocally
        self.retentionAmountS3 = retentionAmountS3
        self.retentionDaysS3 = retentionDaysS3
        self.retentionMaxStorageS3 = retentionMaxStorageS3
        self.timeout = timeout
    }

    enum CodingKeys: String, CodingKey {
        case uuid
        case message
        case storageUuid
        case storageType
        case frequency
        case enabled
        case saveS3
        case disableLocalBackup
        case stopDuringBackup
        case s3StorageUuid
        case retentionAmountLocally
        case retentionDaysLocally
        case retentionMaxStorageLocally
        case retentionAmountS3
        case retentionDaysS3
        case retentionMaxStorageS3
        case timeout
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = container.flexString(.uuid) ?? ""
        message = container.flexString(.message)
        storageUuid = container.flexString(.storageUuid)
        storageType = container.flexString(.storageType)
        frequency = container.flexString(.frequency) ?? ""
        enabled = container.flexBool(.enabled) ?? true
        saveS3 = container.flexBool(.saveS3) ?? false
        disableLocalBackup = container.flexBool(.disableLocalBackup) ?? false
        stopDuringBackup = container.flexBool(.stopDuringBackup) ?? false
        s3StorageUuid = container.flexString(.s3StorageUuid)
        retentionAmountLocally = container.flexInt(.retentionAmountLocally)
        retentionDaysLocally = container.flexInt(.retentionDaysLocally)
        retentionMaxStorageLocally = container.flexDouble(.retentionMaxStorageLocally)
        retentionAmountS3 = container.flexInt(.retentionAmountS3)
        retentionDaysS3 = container.flexInt(.retentionDaysS3)
        retentionMaxStorageS3 = container.flexDouble(.retentionMaxStorageS3)
        timeout = container.flexInt(.timeout)
    }
}

/// The body for `PUT /{kind}/{uuid}/storages/{storage_uuid}/backups`.
///
/// `frequency` is required: a cron expression, or `hourly`, `daily`, `weekly`, `monthly`, or `yearly`.
/// Nil optionals are left out. Coolify 4.3 answers 422 to a key it does not expect.
public struct VolumeBackupScheduleRequest: Encodable, Sendable, Hashable {
    public var frequency: String
    public var enabled: Bool?
    public var saveS3: Bool?
    public var disableLocalBackup: Bool?
    public var stopDuringBackup: Bool?
    public var s3StorageUuid: String?
    public var retentionAmountLocally: Int?
    public var retentionDaysLocally: Int?
    public var retentionMaxStorageLocally: Double?
    public var retentionAmountS3: Int?
    public var retentionDaysS3: Int?
    public var retentionMaxStorageS3: Double?
    public var timeout: Int?

    public init(
        frequency: String,
        enabled: Bool? = nil,
        saveS3: Bool? = nil,
        disableLocalBackup: Bool? = nil,
        stopDuringBackup: Bool? = nil,
        s3StorageUuid: String? = nil,
        retentionAmountLocally: Int? = nil,
        retentionDaysLocally: Int? = nil,
        retentionMaxStorageLocally: Double? = nil,
        retentionAmountS3: Int? = nil,
        retentionDaysS3: Int? = nil,
        retentionMaxStorageS3: Double? = nil,
        timeout: Int? = nil
    ) {
        self.frequency = frequency
        self.enabled = enabled
        self.saveS3 = saveS3
        self.disableLocalBackup = disableLocalBackup
        self.stopDuringBackup = stopDuringBackup
        self.s3StorageUuid = s3StorageUuid
        self.retentionAmountLocally = retentionAmountLocally
        self.retentionDaysLocally = retentionDaysLocally
        self.retentionMaxStorageLocally = retentionMaxStorageLocally
        self.retentionAmountS3 = retentionAmountS3
        self.retentionDaysS3 = retentionDaysS3
        self.retentionMaxStorageS3 = retentionMaxStorageS3
        self.timeout = timeout
    }

    enum CodingKeys: String, CodingKey {
        case frequency
        case enabled
        case saveS3
        case disableLocalBackup
        case stopDuringBackup
        case s3StorageUuid
        case retentionAmountLocally
        case retentionDaysLocally
        case retentionMaxStorageLocally
        case retentionAmountS3
        case retentionDaysS3
        case retentionMaxStorageS3
        case timeout
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(frequency, forKey: .frequency)
        try container.encodeIfPresent(enabled, forKey: .enabled)
        try container.encodeIfPresent(saveS3, forKey: .saveS3)
        try container.encodeIfPresent(disableLocalBackup, forKey: .disableLocalBackup)
        try container.encodeIfPresent(stopDuringBackup, forKey: .stopDuringBackup)
        try container.encodeIfPresent(s3StorageUuid, forKey: .s3StorageUuid)
        try container.encodeIfPresent(retentionAmountLocally, forKey: .retentionAmountLocally)
        try container.encodeIfPresent(retentionDaysLocally, forKey: .retentionDaysLocally)
        try container.encodeIfPresent(retentionMaxStorageLocally, forKey: .retentionMaxStorageLocally)
        try container.encodeIfPresent(retentionAmountS3, forKey: .retentionAmountS3)
        try container.encodeIfPresent(retentionDaysS3, forKey: .retentionDaysS3)
        try container.encodeIfPresent(retentionMaxStorageS3, forKey: .retentionMaxStorageS3)
        try container.encodeIfPresent(timeout, forKey: .timeout)
    }
}

extension KeyedDecodingContainer {
    fileprivate func flexDouble(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = flexInt(key) {
            return Double(value)
        }
        if let value = flexString(key) {
            return Double(value)
        }
        return nil
    }
}

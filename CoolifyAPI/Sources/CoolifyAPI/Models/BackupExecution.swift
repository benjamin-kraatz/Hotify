import Foundation

/// The outcome of one database backup, including Coolify's failure message.
public struct BackupExecution: Decodable, Sendable, Identifiable {
    public var uuid: String
    public var status: String
    public var message: String?
    public var filename: String?
    public var size: Int?
    public var createdAt: String?
    /// The database this run dumped, when the schedule backs up more than one.
    public var databaseName: String?
    /// Whether Coolify copied the dump to the schedule's S3 store. Older runs leave this unset.
    public var s3Uploaded: Bool?
    /// Retention removed the dump from the server.
    public var localStorageDeleted: Bool?
    /// Retention removed the dump from S3.
    public var s3StorageDeleted: Bool?
    public var id: String { uuid }
    public var createdAtDate: Date? { createdAt.flatMap(CoolifyTimestamp.parse) }
    public var isSuccessful: Bool { status.lowercased() == "success" }

    enum CodingKeys: String, CodingKey {
        case uuid, status, message, filename, size, createdAt, databaseName
        // `s3_uploaded` and `s3_storage_deleted` become `s3Uploaded` and `s3StorageDeleted` after snake_case conversion.
        case s3Uploaded, localStorageDeleted, s3StorageDeleted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = container.flexString(.uuid) ?? ""
        status = container.flexString(.status) ?? "unknown"
        message = container.flexString(.message)
        filename = container.flexString(.filename)
        size = container.flexInt(.size)
        createdAt = container.flexString(.createdAt)
        databaseName = container.flexString(.databaseName)
        s3Uploaded = container.flexBool(.s3Uploaded)
        localStorageDeleted = container.flexBool(.localStorageDeleted)
        s3StorageDeleted = container.flexBool(.s3StorageDeleted)
    }
}

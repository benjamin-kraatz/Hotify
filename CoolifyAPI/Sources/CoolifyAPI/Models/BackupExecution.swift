import Foundation

/// The outcome of one database backup, including Coolify's failure message.
public struct BackupExecution: Decodable, Sendable, Identifiable {
    public var uuid: String
    public var status: String
    public var message: String?
    public var filename: String?
    public var size: Int?
    public var createdAt: String?
    public var id: String { uuid }
    public var createdAtDate: Date? { createdAt.flatMap(CoolifyTimestamp.parse) }

    enum CodingKeys: String, CodingKey { case uuid, status, message, filename, size, createdAt }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = container.flexString(.uuid) ?? ""
        status = container.flexString(.status) ?? "unknown"
        message = container.flexString(.message)
        filename = container.flexString(.filename)
        size = container.flexInt(.size)
        createdAt = container.flexString(.createdAt)
    }
}

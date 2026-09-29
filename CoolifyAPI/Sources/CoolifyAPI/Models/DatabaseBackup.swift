import Foundation

/// An existing database backup configuration and its execution history.
public struct DatabaseBackup: Decodable, Sendable, Identifiable {
    public var uuid: String
    public var enabled: Bool
    public var frequency: String?
    public var databasesToBackup: String?
    public var executions: [BackupExecution]
    public var id: String { uuid }

    enum CodingKeys: String, CodingKey { case uuid, enabled, frequency, databasesToBackup, executions }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = container.flexString(.uuid) ?? ""
        enabled = container.flexBool(.enabled) ?? false
        frequency = container.flexString(.frequency)
        databasesToBackup = container.flexString(.databasesToBackup)
        executions = try container.decodeIfPresent([BackupExecution].self, forKey: .executions) ?? []
    }
}

import Foundation

/// Where Coolify's import activity stands.
public enum DatabaseImportPhase: Sendable, Hashable {
    case queued
    case inProgress
    case finished
    case error
    case killed
    case cancelled
    case closed
    case other(String)

    public init(rawValue: String?) {
        switch rawValue?.lowercased() {
        case "queued": self = .queued
        case "in_progress": self = .inProgress
        case "finished": self = .finished
        case "error": self = .error
        case "killed": self = .killed
        case "cancelled": self = .cancelled
        case "closed": self = .closed
        default: self = .other(rawValue ?? "")
        }
    }

    public var rawValue: String {
        switch self {
        case .queued: "queued"
        case .inProgress: "in_progress"
        case .finished: "finished"
        case .error: "error"
        case .killed: "killed"
        case .cancelled: "cancelled"
        case .closed: "closed"
        case .other(let value): value
        }
    }

    /// Coolify sets `finished_at` for these. An unknown status counts as still running.
    public var isTerminal: Bool {
        switch self {
        case .finished, .error, .killed, .cancelled, .closed: true
        case .queued, .inProgress, .other: false
        }
    }
}

/// The answer to `POST …/imports`: the activity Coolify queued.
public struct QueuedDatabaseImport: Decodable, Sendable, Hashable {
    public var id: Int
    public var phase: DatabaseImportPhase
    public var message: String?

    enum CodingKeys: String, CodingKey { case id, status, message }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = container.flexInt(.id) else {
            throw DecodingError.dataCorruptedError(
                forKey: .id, in: container, debugDescription: "The queued import has no activity id.")
        }
        self.id = id
        // Coolify 4.4 reads the status from the new activity's properties, which can still be unset.
        phase = DatabaseImportPhase(rawValue: container.flexString(.status) ?? "queued")
        message = container.flexString(.message)
    }
}

/// One import activity as Coolify reports it.
public struct DatabaseImportStatus: Decodable, Sendable, Hashable {
    public var id: Int
    public var phase: DatabaseImportPhase
    public var exitCode: Int?
    /// The restore's output. `nil` when the token may not read sensitive data.
    public var output: String?
    public var createdAt: String?
    public var updatedAt: String?
    public var finishedAt: String?

    public var isTerminal: Bool { phase.isTerminal }

    /// Only a finished activity that did not report a failing exit code restored the backup.
    public var succeeded: Bool { phase == .finished && (exitCode ?? 0) == 0 }

    enum CodingKeys: String, CodingKey { case id, status, exitCode, output, createdAt, updatedAt, finishedAt }

    public init(
        id: Int,
        phase: DatabaseImportPhase,
        exitCode: Int? = nil,
        output: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        finishedAt: String? = nil
    ) {
        self.id = id
        self.phase = phase
        self.exitCode = exitCode
        self.output = output
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.finishedAt = finishedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.flexInt(.id) ?? 0
        phase = DatabaseImportPhase(rawValue: container.flexString(.status))
        exitCode = container.flexInt(.exitCode)
        output = container.flexString(.output)
        createdAt = container.flexString(.createdAt)
        updatedAt = container.flexString(.updatedAt)
        finishedAt = container.flexString(.finishedAt)
    }
}

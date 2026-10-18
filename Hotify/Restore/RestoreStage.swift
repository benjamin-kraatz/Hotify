import Foundation

/// Where one restore is, from the first uploaded byte to Coolify's final word.
enum RestoreStage: Hashable {
    case uploading
    case starting
    case queued
    case restoring
    /// Coolify reported `finished`, and nothing else counts as success.
    case succeeded
    /// The upload or the start was refused, or Coolify reported the import as anything but finished.
    case failed
    case uploadCancelled
    /// Hotify could not read the status several times in a row. The import may still run in Coolify.
    case lostTrack

    /// Hotify is still uploading, starting, or following it. Another restore of the same database waits.
    var isActive: Bool {
        switch self {
        case .uploading, .starting, .queued, .restoring: true
        case .succeeded, .failed, .uploadCancelled, .lostTrack: false
        }
    }

    var heat: Heat {
        switch self {
        case .uploading, .starting, .queued, .restoring: .warming
        case .succeeded: .lit
        case .failed, .lostTrack: .troubled
        case .uploadCancelled: .cold
        }
    }

    var title: String {
        switch self {
        case .uploading: "Uploading…"
        case .starting: "Starting the import…"
        case .queued: "Queued"
        case .restoring: "Restoring…"
        case .succeeded: "Restored"
        case .failed: "Restore failed"
        case .uploadCancelled: "Upload cancelled"
        case .lostTrack: "Status unknown"
        }
    }
}

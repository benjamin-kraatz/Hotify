import CoolifyAPI
import Foundation

extension BackupExecution {
    /// Coolify still has this backup queued or running.
    var isUnderway: Bool {
        ["running", "in_progress", "queued"].contains(status)
    }

    var heat: Heat {
        switch status {
        case "success", "finished": .lit
        case "failed", "error": .troubled
        default: isUnderway ? .warming : .unknown
        }
    }

    var statusLabel: String {
        switch status {
        case "success", "finished": "Backed up"
        case "failed", "error": "Failed"
        case "queued": "Queued"
        case "running", "in_progress": "Backing up…"
        default: status.prefix(1).uppercased() + status.dropFirst()
        }
    }

    /// The file size, when Coolify recorded one. A failed backup reports `0`.
    var sizeLabel: String? {
        guard let size, size > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

import Foundation

/// One restore Hotify started, in plain values the progress view and the banner read.
struct RestoreJob: Identifiable, Hashable {
    let id = UUID()
    var target: RestoreTarget
    /// Where the backup comes from, such as the file's name or the run's date.
    var sourceLabel: String
    var stage: RestoreStage
    var sentBytes: Int64 = 0
    var totalBytes: Int64 = 0
    /// Coolify's activity, once the import is queued.
    var activityID: Int?
    /// Coolify's own word for the import's state, such as `error` or `killed`.
    var coolifyStatus: String?
    var exitCode: Int?
    /// `nil` until Coolify sends it. Coolify leaves it out for a token that may not read sensitive data.
    var output: String?
    /// Why it failed or lost track, in words for the user.
    var problem: String?
    var startedAt = Date.now
    var finishedAt: Date?

    var fraction: Double {
        totalBytes > 0 ? min(1, Double(sentBytes) / Double(totalBytes)) : 0
    }

    /// The one-line state the banner shows under the target's name.
    var summary: String {
        switch stage {
        case .uploading:
            let sent = ByteCountFormatter.string(fromByteCount: sentBytes, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            return "Uploading \(sent) of \(total)"
        case .starting: return "Asking Coolify to start the import"
        case .queued: return "Coolify has the import queued"
        case .restoring: return "Coolify is restoring \(sourceLabel)"
        case .succeeded: return "Coolify restored \(sourceLabel)"
        case .failed: return problem ?? "Coolify reported the import as \(coolifyStatus ?? "failed")"
        case .uploadCancelled: return "Nothing was imported"
        case .lostTrack: return "It may still be running in Coolify"
        }
    }
}

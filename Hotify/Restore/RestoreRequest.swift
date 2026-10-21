import CoolifyAPI
import Foundation

/// What the sheet hands the store: the target, where the backup comes from, and the options that apply.
struct RestoreRequest {
    enum Origin {
        /// Uploaded first, then imported.
        case file(RestoreFile)
        /// Already on the server or in S3.
        case stored(DatabaseImportSource)
    }

    var target: RestoreTarget
    var origin: Origin
    var options: DatabaseImportOptions
    var sourceLabel: String
}

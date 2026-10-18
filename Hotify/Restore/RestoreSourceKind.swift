import Foundation

/// Where a restore reads its backup from.
enum RestoreSourceKind: String, CaseIterable, Identifiable {
    case file
    case run
    case path

    var id: String { rawValue }

    var title: String {
        switch self {
        case .file: "File on this device"
        case .run: "Backup run"
        case .path: "Path on the server"
        }
    }
}

/// Which stored copy of a backup run to import.
enum StoredCopy: Hashable {
    case server
    case s3
}

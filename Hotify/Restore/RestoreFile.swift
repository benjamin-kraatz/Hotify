import CoolifyAPI
import Foundation

/// A backup file picked on this device, checked the way Coolify checks it before any byte goes out.
struct RestoreFile: Hashable {
    var url: URL
    var name: String
    var size: Int64

    /// Reads the name and size. The picker's URL is security-scoped, so this asks for access while it reads.
    init(url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .totalFileSizeKey, .nameKey])
        self.url = url
        name = values.name ?? url.lastPathComponent
        size = Int64(values.fileSize ?? values.totalFileSize ?? 0)
    }

    init(url: URL, name: String, size: Int64) {
        self.url = url
        self.name = name
        self.size = size
    }

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// What Coolify would refuse about this file, worded for the person picking it.
    var problem: String? {
        if DatabaseImportFile.allowedExtension(for: name) == nil {
            return "Coolify does not take \(name). Pick a backup ending in .sql, .sql.gz, .dmp, .dump, .tar, .gz, "
                + ".archive, .db, .sqlite, or a similar backup extension."
        }
        if size <= 0 {
            return "\(name) is empty."
        }
        if size > DatabaseImportFile.maxBytes {
            let limit = ByteCountFormatter.string(fromByteCount: DatabaseImportFile.maxBytes, countStyle: .file)
            return "\(name) is \(sizeLabel). Coolify takes backups up to \(limit)."
        }
        return nil
    }
}

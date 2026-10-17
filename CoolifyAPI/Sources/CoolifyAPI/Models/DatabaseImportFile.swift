import Foundation

/// The backup files Coolify 4.4 accepts for an upload, checked before any byte is sent.
///
/// Coolify checks again on its side, including that the content matches the extension.
public enum DatabaseImportFile {
    /// Coolify refuses a backup larger than 10 GiB.
    public static let maxBytes: Int64 = 10 * 1_024 * 1_024 * 1_024

    /// Each upload request carries one chunk of this size. Coolify's own upload sends 10 MB chunks, so this stays under
    /// the request size its PHP accepts.
    public static let chunkSize = 8 * 1_024 * 1_024

    /// Longest first, so `backup.sql.gz` reads as `sql.gz` and not `gz`.
    public static let allowedExtensions: [String] = [
        "sql", "sql.gz", "gz", "zip", "tar", "tar.gz", "tgz", "dump", "bak", "bson", "bson.gz", "archive",
        "archive.gz", "bz2", "xz", "dmp", "db", "db.gz", "sqlite", "sqlite.gz", "sqlite3", "sqlite3.gz",
    ].sorted { $0.count > $1.count }

    /// A name with one of these parts, such as `dump.php.sql`, is refused.
    private static let scriptExtensions: Set<String> = [
        "asp", "aspx", "bat", "bash", "cgi", "cmd", "com", "exe", "htm", "html", "jar", "js", "jsp", "php", "php3",
        "php4", "php5", "phtml", "pl", "ps1", "py", "rb", "sh",
    ]

    /// The extension Coolify reads from `filename`, or `nil` when Coolify would refuse the name.
    public static func allowedExtension(for filename: String) -> String? {
        let name = (filename as NSString).lastPathComponent.lowercased()
        guard let match = allowedExtensions.first(where: { name.hasSuffix("." + $0) }) else { return nil }
        let stem = name.dropLast(match.count + 1)
        guard !stem.isEmpty, !stem.hasSuffix(".") else { return nil }
        let parts = stem.split(separator: ".").map(String.init)
        guard scriptExtensions.isDisjoint(with: parts) else { return nil }
        return match
    }
}

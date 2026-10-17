import Foundation

/// Quoting for the POSIX shell on a server, where the terminal's commands run.
public enum Shell {
    /// Wraps a value in single quotes, so it reaches the command as one word, unchanged.
    public static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}

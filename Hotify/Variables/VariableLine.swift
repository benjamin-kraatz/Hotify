import CoolifyAPI
import Foundation

/// One environment variable row. Built from `EnvironmentVariable` so the view can take plain values in a preview.
struct VariableLine: Identifiable, Hashable {
    var id: String
    var key: String
    /// `nil` when Coolify withheld the value, which is not the same as an empty one.
    var value: String?
    /// The value with shared references such as `{{team.API_URL}}` filled in, when that differs from `value`.
    var resolvedValue: String?
    var isPreview = false
    var isLiteral = false
    var isMultiline = false
    var isShownOnce = false
    var isRuntime: Bool?
    var isBuildtime: Bool?
    var comment: String?

    /// Short facts for the row, such as `Literal`. Nothing for a plain variable.
    var tags: [String] {
        var tags: [String] = []
        if isBuildtime == true, isRuntime == false {
            tags.append("Build only")
        } else if isRuntime == true, isBuildtime == false {
            tags.append("Runtime only")
        }
        if isLiteral {
            tags.append("Literal")
        }
        if isMultiline {
            tags.append("Multiline")
        }
        if isShownOnce {
            tags.append("Hidden")
        }
        return tags
    }

    /// The line for a `.env` file, quoted when the value would not survive as written.
    var dotenvLine: String? {
        guard let value else { return nil }
        let needsQuotes = value.contains { $0.isWhitespace || "#\"'$\\".contains($0) }
        guard needsQuotes else { return "\(key)=\(value)" }
        let escaped =
            value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\(key)=\"\(escaped)\""
    }
}

extension VariableLine {
    init(variable: EnvironmentVariable) {
        id = variable.uuid.isEmpty ? "\(variable.isPreview)-\(variable.key)" : variable.uuid
        key = variable.key
        value = variable.value
        if let real = variable.realValue, !real.isEmpty, real != variable.value {
            resolvedValue = real
        }
        isPreview = variable.isPreview
        isLiteral = variable.isLiteral
        isMultiline = variable.isMultiline
        isShownOnce = variable.isShownOnce
        isRuntime = variable.isRuntime
        isBuildtime = variable.isBuildtime
        if let comment = variable.comment?.trimmingCharacters(in: .whitespacesAndNewlines), !comment.isEmpty {
            self.comment = comment
        }
    }
}

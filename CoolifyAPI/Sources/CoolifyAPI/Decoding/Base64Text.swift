import Foundation

/// Coolify stores some text fields, such as `custom_labels`, as base64 and sends them that way.
enum Base64Text {
    /// The decoded text, or `text` itself when it is not base64 of UTF-8. Older instances and the tests send
    /// plain labels, and a label block always holds `=` or `.` in places base64 never does.
    static func decode(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            let data = Data(base64Encoded: trimmed),
            let decoded = String(data: data, encoding: .utf8)
        else { return text }
        return decoded
    }

    static func encode(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }
}

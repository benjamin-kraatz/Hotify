import Foundation

/// Looks at text about to be pasted into a shell, and says what the shell would do with it.
///
/// A shell runs each line it gets, so a multi-line paste is a script, and a control character can be a
/// keystroke such as Ctrl-C. Both deserve a look first. One plain line goes straight through.
struct PasteCheck {
    var text: String

    /// How many lines the paste holds, counting a trailing newline as a line the shell runs.
    var lineCount: Int {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        return text.last?.isNewline == true ? lines.count : max(lines.count, 1)
    }

    /// Whether the text holds a control character other than a newline or a tab.
    var hasControlCharacters: Bool {
        text.unicodeScalars.contains { scalar in
            scalar.value < 0x20 && scalar != "\n" && scalar != "\r" && scalar != "\t" || scalar.value == 0x7F
        }
    }

    var needsConfirmation: Bool {
        lineCount > 1 || hasControlCharacters
    }

    /// The question to ask, such as `Paste 3 lines?`.
    var question: String {
        if lineCount > 1 {
            return "Paste \(lineCount) lines?"
        }
        return "Paste control characters?"
    }

    var explanation: String {
        var reasons: [String] = []
        if lineCount > 1 {
            reasons.append("The shell runs each line as it arrives.")
        }
        if hasControlCharacters {
            reasons.append("The text holds control characters, which the shell reads as keystrokes.")
        }
        return reasons.joined(separator: " ")
    }

    /// The text as the terminal sends it: Return between lines, the way a keyboard would, and no trailing newline
    /// beyond the one the paste had.
    var normalized: String {
        text.replacingOccurrences(of: "\r\n", with: "\r").replacingOccurrences(of: "\n", with: "\r")
    }
}

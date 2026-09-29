import Foundation

/// One line of container output, split into its Docker timestamp and its message.
struct LogLine: Identifiable, Hashable {
    var id: Int
    var timestamp: Date?
    var text: String
    /// The message mentions an error, a failure, or a warning.
    var isAlarming: Bool

    private static let alarmWords = ["error", "fatal", "panic", "exception", "fail", "warn", "critical"]

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let wholeSecondFormatter = ISO8601DateFormatter()

    /// Splits logs fetched with `showTimestamps`. Lines without a leading timestamp keep their full text.
    static func parse(_ logs: String) -> [LogLine] {
        var lines: [LogLine] = []
        for (index, raw) in logs.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.hasSuffix("\r") ? raw.dropLast() : raw
            var timestamp: Date?
            var text = Substring(line)
            if let space = line.firstIndex(of: " "), let date = parseTimestamp(line[..<space]) {
                timestamp = date
                text = line[line.index(after: space)...]
            }
            let lowered = text.lowercased()
            lines.append(
                LogLine(
                    id: index,
                    timestamp: timestamp,
                    text: String(text),
                    isAlarming: alarmWords.contains { lowered.contains($0) }
                )
            )
        }
        while lines.last?.text.isEmpty == true {
            lines.removeLast()
        }
        return lines
    }

    /// Docker writes nanoseconds, which `ISO8601DateFormatter` rejects, so the fraction is cut to milliseconds.
    private static func parseTimestamp(_ token: Substring) -> Date? {
        guard token.count >= 20, token.dropFirst(10).first == "T" else { return nil }
        let value = String(token)
        guard let dot = value.firstIndex(of: "."),
            let zone = value[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" })
        else {
            return wholeSecondFormatter.date(from: value)
        }
        let digits = value[value.index(after: dot)..<zone].prefix(3)
        let milliseconds = digits.padding(toLength: 3, withPad: "0", startingAt: 0)
        return fractionalFormatter.date(from: value[..<dot] + "." + milliseconds + value[zone...])
    }
}

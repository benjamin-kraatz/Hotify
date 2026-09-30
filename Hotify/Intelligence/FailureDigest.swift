import Foundation

/// The part of a build log that fits the on-device model: its end, and the problem lines before it.
struct FailureDigest {
    /// The chosen lines in log order.
    private(set) var lines: [LogLine] = []

    private static let tailCount = 30
    private static let longestLine = 240

    /// Picks lines until `budget` characters are spent. A failure ends the output, so the tail goes first,
    /// then problem lines further up with a line of context on each side, then whatever else still fits.
    init(lines all: [LogLine], budget: Int) {
        let candidates = all.filter { !$0.text.allSatisfy(\.isWhitespace) }
        var picked = Set<Int>()
        var spent = 0

        func take(_ index: Int) {
            guard candidates.indices.contains(index), !picked.contains(index) else { return }
            let cost = min(candidates[index].text.count, Self.longestLine) + 1
            guard spent + cost <= budget else { return }
            spent += cost
            picked.insert(index)
        }

        let tail = candidates.indices.suffix(Self.tailCount)
        tail.reversed().forEach(take)
        for index in candidates.indices.dropLast(tail.count).reversed() where candidates[index].isAlarming {
            [index, index + 1, index - 1].forEach(take)
        }
        candidates.indices.reversed().forEach(take)

        lines = picked.sorted().map { candidates[$0] }
    }

    var prompt: String {
        "Build output:\n" + lines.map { $0.text.prefix(Self.longestLine) }.joined(separator: "\n")
    }

    /// The first line that holds what the model quoted, or `nil` when the quote is not in the log.
    func line(quoting quote: String) -> LogLine? {
        // The model sometimes escapes quotation marks it copied.
        let wanted = quote.replacing("\\", with: "").trimmingCharacters(in: .whitespaces)
        // Anything shorter matches lines by accident.
        guard wanted.count >= 8 else { return nil }
        return lines.first { $0.text.contains(wanted) }
    }
}

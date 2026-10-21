import Foundation

/// What Hotify can tell about a compose file before Coolify sees it, without a YAML parser.
///
/// Only an empty file blocks a save. Everything else is advice, because a file this reader does not follow, such as
/// one in flow style, JSON, or with anchors, can still be valid compose. Coolify has the last word.
public struct ComposeCheck: Sendable, Hashable {
    /// One thing worth knowing about the file.
    public struct Finding: Sendable, Hashable, Identifiable {
        public enum Severity: Sendable, Hashable {
            /// Coolify would refuse it for certain, so saving waits.
            case blocking
            /// Likely a mistake, but the file may still be fine.
            case advice
        }

        public var severity: Severity
        /// The 1-based line the finding is about, if it is about one.
        public var line: Int?
        public var message: String

        public var id: String { "\(line ?? 0):\(message)" }
    }

    public var findings: [Finding]

    public init(_ compose: String) {
        findings = Self.findings(in: compose)
    }

    /// Whether a finding stops the file from being saved.
    public var isBlocking: Bool {
        findings.contains { $0.severity == .blocking }
    }

    private static func findings(in compose: String) -> [Finding] {
        guard !compose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return [Finding(severity: .blocking, line: nil, message: "The compose file is empty.")]
        }
        var result: [Finding] = []
        let lines = compose.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)

        if let tabbed = lines.firstIndex(where: { line in
            line.prefix { $0 == " " || $0 == "\t" }.contains("\t")
        }) {
            result.append(
                Finding(
                    severity: .advice,
                    line: tabbed + 1,
                    message: "Line \(tabbed + 1) is indented with a tab. YAML only allows spaces there."
                )
            )
        }

        let topLevel = lines.filter { line in
            guard let first = line.first else { return false }
            return first != " " && first != "\t" && first != "#"
        }
        // JSON and flow style hold their keys inside braces, which this reader does not follow.
        let isFlow = compose.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{")
        let hasServices = topLevel.contains { line in
            let key = line.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
            return key.trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")) == "services"
        }
        if !isFlow, !hasServices {
            result.append(
                Finding(
                    severity: .advice,
                    line: nil,
                    message: "There is no top-level services: key. Coolify needs one to know what to run."
                )
            )
        }

        if let building = buildLine(in: lines) {
            result.append(
                Finding(
                    severity: .advice,
                    line: building + 1,
                    message:
                        "Line \(building + 1) builds an image. A service has no repository to build from, so give it an image, or create a Docker Compose application instead."
                )
            )
        }
        return result
    }

    /// The first `build:` key inside a container, which a Coolify service cannot follow.
    private static func buildLine(in lines: [Substring]) -> Int? {
        lines.firstIndex { line in
            let indent = line.prefix { $0 == " " }.count
            let trimmed = line.drop { $0 == " " }
            return indent > 0 && (trimmed == "build:" || trimmed.hasPrefix("build: ") || trimmed.hasPrefix("build:\t"))
        }
    }
}

import Foundation

/// Build output returned either as text, a JSON-encoded list, or an expanded list of log entries.
public struct DeploymentOutput: Decodable, Sendable {
    public let text: String

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let entries = try? container.decode([Entry].self) {
            text = Self.render(entries)
        } else {
            let raw = try container.decode(String.self)
            // Coolify stores deployment logs as a JSON string inside the deployment response.
            if let entries = try? CoolifyJSON.decoder().decode([Entry].self, from: Data(raw.utf8)) {
                text = Self.render(entries)
            } else {
                text = raw
            }
        }
    }

    private static func render(_ entries: [Entry]) -> String {
        entries.map { entry in
            [entry.timestamp, entry.output].compactMap { $0 }.joined(separator: " ")
        }.joined(separator: "\n")
    }

    private struct Entry: Decodable {
        var output: String?
        var timestamp: String?

        enum CodingKeys: String, CodingKey { case output, timestamp }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            output = container.flexString(.output)
            timestamp = container.flexString(.timestamp)
        }
    }
}

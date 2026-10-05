import Foundation

/// A schedule Coolify will store. The API field is a free string: a name such as `hourly`, or any cron expression.
enum TaskFrequency: Hashable, Identifiable, CaseIterable {
    case hourly
    case daily
    case weekly
    case monthly
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .hourly: "Hourly"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .custom: "Custom"
        }
    }

    /// The named schedule Coolify accepts. Custom has no fixed value.
    var named: String? {
        switch self {
        case .hourly: "hourly"
        case .daily: "daily"
        case .weekly: "weekly"
        case .monthly: "monthly"
        case .custom: nil
        }
    }

    /// The preset a stored frequency already is, or custom when it is a cron string of its own.
    static func match(_ raw: String) -> TaskFrequency {
        switch normalize(raw) {
        case "hourly", "@hourly", "0 * * * *": .hourly
        case "daily", "@daily", "@midnight", "0 0 * * *": .daily
        case "weekly", "@weekly", "0 0 * * 0": .weekly
        case "monthly", "@monthly", "0 0 1 * *": .monthly
        default: .custom
        }
    }

    /// A preset's name, or the frequency as Coolify stored it.
    static func label(for raw: String) -> String {
        let match = match(raw)
        return match == .custom ? raw : match.title
    }

    private static func normalize(_ raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
}

import CoolifyAPI
import Foundation

extension DatabaseBackup {
    /// About how long the schedule waits between runs, for telling when a backup is overdue.
    ///
    /// Coolify stores one of its own words or a cron line. A cron line too irregular to read, such as one that runs
    /// on a list of weekdays, gives `nil`, and nothing is called overdue.
    var expectedInterval: TimeInterval? {
        guard enabled, let frequency, !frequency.isEmpty else { return nil }
        let day: TimeInterval = 86_400
        switch frequency {
        case "every_minute": return 60
        case "hourly": return 3_600
        case "daily": return day
        case "weekly": return 7 * day
        case "monthly": return 31 * day
        case "yearly": return 366 * day
        default: break
        }
        let fields = frequency.split(separator: " ").map(String.init)
        guard fields.count == 5 else { return nil }
        let (minute, hour, dayOfMonth, month, weekday) = (fields[0], fields[1], fields[2], fields[3], fields[4])
        func isSingle(_ field: String) -> Bool { Int(field) != nil }
        func step(_ field: String) -> Double? {
            field.hasPrefix("*/") ? Double(field.dropFirst(2)).flatMap { $0 > 0 ? $0 : nil } : nil
        }

        if weekday != "*" {
            return isSingle(weekday) && dayOfMonth == "*" ? 7 * day : nil
        }
        if dayOfMonth != "*" {
            guard isSingle(dayOfMonth) else { return nil }
            return month == "*" ? 31 * day : (isSingle(month) ? 366 * day : nil)
        }
        if hour != "*" {
            if isSingle(hour) { return day }
            return step(hour).map { $0 * 3_600 }
        }
        if minute == "*" { return 60 }
        if isSingle(minute) { return 3_600 }
        return step(minute).map { $0 * 60 }
    }
}

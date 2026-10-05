import CoolifyAPI
import Foundation

extension DatabaseBackup {
    /// Newest first.
    var history: [BackupExecution] {
        executions.sorted { ($0.createdAtDate ?? .distantPast) > ($1.createdAtDate ?? .distantPast) }
    }

    /// The databases this configuration dumps, when Coolify names them.
    var databaseNames: String? {
        if dumpAll { return "All databases" }
        guard let names = databasesToBackup?.trimmingCharacters(in: .whitespaces), !names.isEmpty else { return nil }
        return names.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ", ")
    }

    /// Coolify stores either one of its own words, such as `daily`, or a cron expression.
    var scheduleLabel: String {
        guard enabled else { return "Schedule off" }
        let words = [
            "every_minute": "Every minute",
            "hourly": "Every hour",
            "daily": "Every day",
            "weekly": "Every week",
            "monthly": "Every month",
            "yearly": "Every year",
        ]
        guard let frequency, !frequency.isEmpty else { return "No schedule" }
        return words[frequency] ?? frequency
    }
}

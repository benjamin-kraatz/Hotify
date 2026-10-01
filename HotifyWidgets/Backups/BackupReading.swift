import CoolifyAPI
import Foundation

/// What a widget last read about one database's backups, across all of its backup configurations.
struct BackupReading: Codable, Hashable {
    var name: String
    var instanceName: String
    /// The engine, such as `PostgreSQL`, when the widget found the database in a list.
    var engine: String?
    var configurations = 0
    var enabledConfigurations = 0
    /// Coolify's word for the newest run, and when it started.
    var lastStatus: String?
    var lastRunAt: Date?
    var lastSuccessAt: Date?
    /// The shortest wait between scheduled runs, when the schedules can be read.
    var interval: TimeInterval?
    /// The configuration Back Up Now runs: the first enabled one, else the first.
    var backupUUID: String?
    var checkedAt: Date?
    var problem: ReadingProblem?

    init(name: String, instanceName: String, engine: String?, backups: [DatabaseBackup], checkedAt: Date) {
        self.name = name
        self.instanceName = instanceName
        self.engine = engine
        configurations = backups.count
        enabledConfigurations = backups.filter(\.enabled).count
        let runs = backups.flatMap(\.history).sorted {
            ($0.createdAtDate ?? .distantPast) > ($1.createdAtDate ?? .distantPast)
        }
        lastStatus = runs.first?.status
        lastRunAt = runs.first?.createdAtDate
        lastSuccessAt = runs.first { $0.heat == .lit }?.createdAtDate
        interval = backups.compactMap(\.expectedInterval).min()
        backupUUID = (backups.first(where: \.enabled) ?? backups.first)?.uuid
        self.checkedAt = checkedAt
    }

    init(name: String, instanceName: String, problem: ReadingProblem) {
        self.name = name
        self.instanceName = instanceName
        self.problem = problem
    }

    /// The last good backup is older than the schedule allows, with room for a slow run.
    func isOverdue(at date: Date) -> Bool {
        guard enabledConfigurations > 0, let interval else { return false }
        guard let lastSuccessAt else { return lastRunAt != nil }
        return date.timeIntervalSince(lastSuccessAt) > interval * 1.5 + 1_800
    }
}

/// A Back Up Now the widget sent, until a newer run shows up.
struct BackupRequest: Codable, Hashable {
    var at: Date
    /// Coolify refused it.
    var failed = false
}

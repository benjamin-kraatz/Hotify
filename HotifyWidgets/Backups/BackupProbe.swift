import CoolifyAPI
import Foundation

/// Reads the backups of the followed databases: one request per database, runs included.
enum BackupProbe {
    /// How many databases a widget follows when none were picked.
    static let automaticLimit = 12

    struct Followed {
        var pin: ResourcePin
        var name: String
        var engine: String?
    }

    struct Result {
        var pins: [ResourcePin]
        var names: [String: String]
        var problems: [String]
        var available: Int?
    }

    /// Reads, folds the readings into the ledger, and says which databases it covered.
    static func read(picked: [ResourceEntity]) async -> Result {
        var followed = picked.compactMap { entity in
            entity.pin.map { Followed(pin: $0, name: entity.name, engine: nil) }
        }
        .filter { $0.pin.route.kind == .database }
        var available: Int?
        if followed.isEmpty {
            let all = await allDatabases()
            available = all.count
            followed = Array(all.prefix(automaticLimit))
        }

        let previous = WidgetLedger.load().backups
        let byInstance = Dictionary(grouping: followed, by: \.pin.instanceID)
        let batches = await withTaskGroup(of: ([String: BackupReading], String?).self) { group in
            for (instanceID, databases) in byInstance {
                group.addTask { await read(databases, on: instanceID, previous: previous) }
            }
            var batches: [([String: BackupReading], String?)] = []
            for await batch in group {
                batches.append(batch)
            }
            return batches
        }
        let fresh = batches.reduce(into: [String: BackupReading]()) { $0.merge($1.0) { _, new in new } }
        WidgetLedger.update { ledger in
            ledger.backups.merge(fresh) { _, new in new }
            // A run newer than a sent request answers it.
            for (id, reading) in fresh {
                if let request = ledger.backupRequests[id], let lastRun = reading.lastRunAt,
                    lastRun >= request.at.addingTimeInterval(-60)
                {
                    ledger.backupRequests[id] = nil
                }
            }
        }
        return Result(
            pins: followed.map(\.pin),
            names: Dictionary(followed.map { ($0.pin.id, $0.name) }) { first, _ in first },
            problems: batches.compactMap(\.1).sorted(),
            available: available)
    }

    private static func read(
        _ databases: [Followed], on instanceID: UUID, previous: [String: BackupReading]
    ) async -> ([String: BackupReading], String?) {
        func failed(_ problem: ReadingProblem, name: String) -> [String: BackupReading] {
            Dictionary(
                uniqueKeysWithValues: databases.map { database in
                    var reading =
                        previous[database.pin.id]
                        ?? BackupReading(name: database.name, instanceName: name, problem: problem)
                    reading.problem = problem
                    return (database.pin.id, reading)
                })
        }
        guard case .success((let instance, let client)) = InstanceAccess.client(for: instanceID) else {
            let name = InstanceAccess.instance(instanceID)?.name ?? ""
            return (failed(.noToken, name: name), ReadingProblem.noToken.message(instanceName: name))
        }
        return await withTaskGroup(of: (String, BackupReading).self) { group in
            for database in databases {
                group.addTask {
                    do {
                        let backups = try await client.databaseBackups(database.pin.route.uuid)
                        let engine = database.engine ?? previous[database.pin.id]?.engine
                        return (
                            database.pin.id,
                            BackupReading(
                                name: database.name, instanceName: instance.name, engine: engine,
                                backups: backups, checkedAt: .now)
                        )
                    } catch {
                        var reading =
                            previous[database.pin.id]
                            ?? BackupReading(name: database.name, instanceName: instance.name, problem: .unreachable)
                        reading.problem = (error as? CoolifyError)?.statusCode == 404 ? .gone : .unreachable
                        return (database.pin.id, reading)
                    }
                }
            }
            var readings: [String: BackupReading] = [:]
            for await (id, reading) in group {
                readings[id] = reading
            }
            let unreachable = !readings.isEmpty && readings.values.allSatisfy { $0.problem == .unreachable }
            return (readings, unreachable ? ReadingProblem.unreachable.message(instanceName: instance.name) : nil)
        }
    }

    /// Every database on every saved instance, one request per instance.
    private static func allDatabases() async -> [Followed] {
        let instances = AppGroup.instances()
        return await withTaskGroup(of: (Int, [Followed]).self) { group in
            for (index, instance) in instances.enumerated() {
                group.addTask {
                    guard case .success((_, let client)) = InstanceAccess.client(for: instance.id),
                        let databases = try? await client.databases()
                    else { return (index, []) }
                    let followed = databases.map { database in
                        let summary = ResourceSummary(database: database)
                        return Followed(
                            pin: ResourcePin(instanceID: instance.id, route: summary.route),
                            name: summary.name, engine: summary.subtitle)
                    }
                    return (index, followed)
                }
            }
            var found: [(Int, [Followed])] = []
            for await result in group {
                found.append(result)
            }
            return found.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
    }
}

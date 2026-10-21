import CoolifyAPI
import Foundation

/// The sheet's choices before a restore starts. Options that do not apply to the engine are never sent.
struct RestoreDraft {
    var kind: RestoreSourceKind = .file
    var file: RestoreFile?
    var runID: String?
    var copy: StoredCopy = .s3
    var path = ""
    var dumpAll = false
    var replaceExisting = false
    var keepOwners = false
    var restoreMySQLUsers = false
    var sqliteDatabase = ""

    func run(in runs: [RestorableRun]) -> RestorableRun? {
        runs.first { $0.id == runID }
    }

    /// The copy the import reads, falling back to the one that exists.
    func storedSource(of run: RestorableRun) -> DatabaseImportSource? {
        switch copy {
        case .s3: run.sources.s3 ?? run.sources.server
        case .server: run.sources.server ?? run.sources.s3
        }
    }

    /// The name the backup goes by, which tells a PostgreSQL archive from SQL.
    func filename(runs: [RestorableRun]) -> String? {
        switch kind {
        case .file: file?.name
        case .run: run(in: runs)?.filename
        case .path: trimmedPath.isEmpty ? nil : trimmedPath
        }
    }

    func format(runs: [RestorableRun]) -> BackupFormat {
        BackupFormat(filename: filename(runs: runs))
    }

    var trimmedPath: String {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Coolify refuses a relative path, `..`, and the characters a shell would read.
    var pathProblem: String? {
        let path = trimmedPath
        if path.isEmpty { return "Enter the backup's path on the server." }
        if !path.hasPrefix("/") { return "The path has to start with /." }
        if path.contains("..") { return "The path can't contain “..”." }
        if path.rangeOfCharacter(from: CharacterSet(charactersIn: "$()`|;&><'\"\\\r\n\0")) != nil {
            return "The path can't contain quotes, $, `, |, ;, &, <, >, or a backslash."
        }
        return nil
    }

    func problems(runs: [RestorableRun]) -> [String] {
        switch kind {
        case .file:
            guard let file else { return ["Choose a backup file."] }
            return file.problem.map { [$0] } ?? []
        case .run:
            return run(in: runs) == nil ? ["Choose a backup run."] : []
        case .path:
            return pathProblem.map { [$0] } ?? []
        }
    }

    /// Only the switches the engine reads, and only in the combinations Coolify accepts.
    func options(for engine: DatabaseImportEngine, format: BackupFormat) -> DatabaseImportOptions {
        var options = DatabaseImportOptions()
        switch engine {
        case .postgresql:
            options.dumpAll = dumpAll
            options.replaceExisting = !dumpAll && replaceExisting
            options.keepOwners = !dumpAll && format != .sql && keepOwners
        case .mysql, .mariadb:
            options.dumpAll = dumpAll
            options.restoreMySQLUsers = dumpAll && restoreMySQLUsers
        case .mongodb:
            options.replaceExisting = replaceExisting
        case .sqlite:
            let name = sqliteDatabase.trimmingCharacters(in: .whitespacesAndNewlines)
            options.sqliteDatabase = name.isEmpty ? nil : name
        }
        return options
    }

    func request(for target: RestoreTarget, runs: [RestorableRun]) -> RestoreRequest? {
        guard let engine = target.engine, problems(runs: runs).isEmpty else { return nil }
        let options = options(for: engine, format: format(runs: runs))
        switch kind {
        case .file:
            guard let file else { return nil }
            return RestoreRequest(target: target, origin: .file(file), options: options, sourceLabel: file.name)
        case .run:
            guard let run = run(in: runs), let source = storedSource(of: run) else { return nil }
            return RestoreRequest(
                target: target, origin: .stored(source), options: options,
                sourceLabel: run.fileName ?? "the backup run")
        case .path:
            let label = (trimmedPath as NSString).lastPathComponent
            return RestoreRequest(
                target: target, origin: .stored(.server(path: trimmedPath)), options: options, sourceLabel: label)
        }
    }
}

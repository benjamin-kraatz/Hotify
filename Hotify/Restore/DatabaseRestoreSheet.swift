import CoolifyAPI
import SwiftUI

/// Restores a backup into a database or a service's database container: where the backup comes from, the engine's
/// options, and what happens to the current data. Once started, it shows the restore's progress in place.
struct DatabaseRestoreSheet: View {
    var target: RestoreTarget
    var client: CoolifyClient?
    /// Successful runs with a stored copy. Only a standalone database has them.
    var runs: [RestorableRun]

    @SwiftUI.Environment(\.dismiss) private var dismiss
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Missing in previews, which leaves Restore off.
    @SwiftUI.Environment(DatabaseRestores.self) private var restores: DatabaseRestores?
    @SwiftUI.Environment(InstanceStore.self) private var instances: InstanceStore?

    @State private var draft: RestoreDraft
    /// Set to show the form while an ended restore of this database is still kept.
    @State private var startsNew: Bool
    @State private var isConfirming = false

    /// `runID` opens the sheet on that run, with its schedule's settings.
    init(target: RestoreTarget, client: CoolifyClient?, runs: [RestorableRun] = [], runID: String? = nil) {
        self.target = target
        self.client = client
        self.runs = runs
        var draft = RestoreDraft()
        if let run = runs.first(where: { $0.id == runID }) {
            draft.kind = .run
            draft.runID = run.id
            draft.dumpAll = run.dumpAll
            draft.copy = run.sources.s3 != nil ? .s3 : .server
        }
        _draft = State(initialValue: draft)
        _startsNew = State(initialValue: runID != nil)
    }

    private var job: RestoreJob? {
        restores?.job(for: target.importTarget)
    }

    /// The running restore always shows. An ended one shows until the user asks for a new restore.
    private var shownJob: RestoreJob? {
        guard let job else { return nil }
        return job.stage.isActive || !startsNew ? job : nil
    }

    private var kinds: [RestoreSourceKind] {
        runs.isEmpty || target.isServiceDatabase ? [.file, .path] : RestoreSourceKind.allCases
    }

    private var format: BackupFormat {
        draft.format(runs: runs)
    }

    private var problems: [String] {
        draft.problems(runs: runs)
    }

    private var canStart: Bool {
        client != nil && restores != nil && target.engine != nil && !target.isKnownStopped && problems.isEmpty
            && restores?.isActive(target.importTarget) != true
    }

    var body: some View {
        NavigationStack {
            Group {
                if let shownJob {
                    RestoreProgressView(
                        job: shownJob,
                        onCancelUpload: { restores?.cancelUpload(target.importTarget) },
                        onCheckAgain: { restores?.checkAgain(target.importTarget) },
                        onNewRestore: { startsNew = true }
                    )
                    .transition(.opacity)
                } else if let engine = target.engine {
                    form(engine: engine)
                        .transition(.opacity)
                } else {
                    RestoreUnavailable(target: target)
                }
            }
            .navigationTitle("Restore Backup")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
            .confirmationDialog(
                "Restore into \(target.name)?",
                isPresented: $isConfirming,
                titleVisibility: .visible
            ) {
                Button(confirmTitle, role: .destructive, action: start)
            } message: {
                Text(confirmMessage)
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 540, minHeight: 580)
        #endif
        .interactiveDismissDisabled(shownJob?.stage == .uploading)
        .animation(reduceMotion ? nil : .snappy, value: shownJob?.id)
        .animation(reduceMotion ? nil : .snappy, value: draft.kind)
        .animation(reduceMotion ? nil : .snappy, value: draft.dumpAll)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if shownJob == nil, target.engine != nil {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Restore…") { isConfirming = true }
                    .disabled(!canStart)
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func form(engine: DatabaseImportEngine) -> some View {
        Form {
            RestoreTargetSection(target: target, instanceName: instances?.selected?.name)
            if target.isKnownStopped {
                Section {
                    Label(
                        "Coolify only imports into a running database. Start \(target.name), then restore.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.glow)
                }
            }
            RestoreSourceSection(draft: $draft, kinds: kinds, runs: runs, engine: engine)
            RestoreOptionsSection(draft: $draft, engine: engine, format: format)
            RestoreConsequenceSection(consequences: consequences(for: engine))
            if let blocking {
                Section {
                    Label(blocking, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.glow)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// What still holds Start back, beyond the problems the source section shows on its own.
    private var blocking: String? {
        if restores?.isActive(target.importTarget) == true {
            return "A restore of \(target.name) is still running. Start another once it ends."
        }
        if client == nil {
            return "Hotify has no connection to this instance."
        }
        return nil
    }

    private func consequences(for engine: DatabaseImportEngine) -> RestoreConsequences {
        RestoreConsequences(engine: engine, options: draft.options(for: engine, format: format), format: format)
    }

    private var confirmTitle: String {
        guard let engine = target.engine else { return "Restore" }
        return consequences(for: engine).replacesData ? "Replace Data" : "Restore"
    }

    private var confirmMessage: String {
        guard let engine = target.engine else { return "" }
        let source = draft.request(for: target, runs: runs)?.sourceLabel ?? "The backup"
        let place = target.serviceName.map { " in \($0)" } ?? ""
        return "\(source) goes into \(target.name)\(place). \(consequences(for: engine).headline) "
            + "Once Coolify queues the import, it can't be stopped."
    }

    private func start() {
        guard canStart, let client, let restores, let request = draft.request(for: target, runs: runs) else { return }
        restores.start(request, client: client)
        startsNew = false
    }
}

#Preview("PostgreSQL") {
    DatabaseRestoreSheet(
        target: RestoreTarget(
            importTarget: .database("db-1"), name: "postgres", engine: .postgresql, status: "running:healthy"),
        client: nil,
        runs: restorePreviewRuns,
        runID: "run-1"
    )
}

#Preview("Stopped MySQL") {
    DatabaseRestoreSheet(
        target: RestoreTarget(importTarget: .database("db-2"), name: "shop", engine: .mysql, status: "exited"),
        client: nil
    )
}

#Preview("Redis") {
    DatabaseRestoreSheet(
        target: RestoreTarget(
            importTarget: .database("db-3"), name: "cache", engine: nil, engineDescription: "Redis",
            status: "running:healthy"),
        client: nil
    )
}

#Preview("Running restore") {
    let target = RestoreTarget(
        importTarget: .database("db-1"), name: "postgres", engine: .postgresql, status: "running:healthy")
    var job = RestoreJob(target: target, sourceLabel: "app.dmp", stage: .restoring)
    job.activityID = 42
    job.output = "pg_restore: creating TABLE public.users"
    return DatabaseRestoreSheet(target: target, client: nil)
        .environment(DatabaseRestores(jobs: [job]))
}

private let restorePreviewRuns: [RestorableRun] = {
    let json = """
        [{"uuid":"daily","enabled":true,"frequency":"daily","dumpAll":false,"saveS3":true,
          "s3StorageUuid":"store-1","executions":[
            {"uuid":"run-1","status":"success","size":48211302,"databaseName":"app",
             "filename":"/data/coolify/backups/databases/app/pg-dump-app-1759118400.dmp",
             "createdAt":"2026-09-29T04:00:00Z"}]}]
        """
    let backups = (try? JSONDecoder().decode([DatabaseBackup].self, from: Data(json.utf8))) ?? []
    return RestorableRun.all(in: backups)
}()

import CoolifyAPI
import SwiftUI

/// A database's backup configurations with their run history, a way to add, edit, delete, or run one, and a way to
/// restore a backup into the database.
struct BackupsView: View {
    var client: CoolifyClient?
    var database: String
    var resourceName: String
    /// The Coolify type, such as `standalone-postgresql`, which decides whether and how a restore works.
    var databaseType: String?
    var status: String?
    @State private var model = BackupsModel()
    @State private var prompt: BackupPrompt?
    @State private var editor: BackupScheduleTarget?
    @State private var restore: RestoreSheetTarget?
    /// Missing in previews, which leaves the restore banner out.
    @SwiftUI.Environment(DatabaseRestores.self) private var restores: DatabaseRestores?
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var restoreTarget: RestoreTarget {
        RestoreTarget(
            database: database,
            name: resourceName,
            databaseType: databaseType,
            engineDescription: ResourceSummary.engineName(databaseType),
            status: status
        )
    }

    private var restoreJob: RestoreJob? {
        restores?.job(for: .database(database))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let restoreJob {
                RestoreBanner(job: restoreJob) { restore = RestoreSheetTarget(runID: nil) }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
            if let error = model.error {
                NoticeBanner(message: error)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !model.backups.isEmpty {
                        addButton
                    }
                    ForEach(model.backups) { backup in
                        BackupCard(
                            backup: backup,
                            fallbackName: resourceName,
                            pendingSince: model.pendingSince(backup),
                            isBusy: model.isBusy(backup),
                            canRun: client != nil && !backup.id.isEmpty,
                            canManage: client != nil && !backup.id.isEmpty,
                            onRun: { prompt = .run(backup) },
                            onEdit: { editor = BackupScheduleTarget(backup: backup) },
                            onDelete: { prompt = .delete(backup) },
                            onRestore: client == nil ? nil : { restore = RestoreSheetTarget(runID: $0.id) }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay { overlay }
        }
        .animation(.snappy, value: model.error)
        .animation(reduceMotion ? nil : .snappy, value: restoreJob?.id)
        .refreshable { if let client { await model.refresh(client: client, database: database) } }
        .task(id: database) { await followHistory() }
        .sheet(item: $editor) { target in
            BackupScheduleEditor(client: client, backup: target.backup) { draft in
                guard let client else { return }
                if let backup = target.backup {
                    try await model.update(backup, with: draft, client: client, database: database)
                } else {
                    try await model.create(draft, client: client, database: database)
                }
            }
        }
        .sheet(item: $restore) { request in
            DatabaseRestoreSheet(
                target: restoreTarget,
                client: client,
                runs: RestorableRun.all(in: model.backups),
                runID: request.runID
            )
        }
        .confirmationDialog(
            promptTitle,
            isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
            titleVisibility: .visible,
            presenting: prompt
        ) { prompt in
            switch prompt {
            case .run(let backup):
                Button("Back Up Now") {
                    guard let client else { return }
                    Task { await model.run(backup, client: client, database: database) }
                }
            case .delete(let backup):
                Button("Delete Schedule", role: .destructive) {
                    guard let client else { return }
                    Task { await model.delete(backup, client: client, database: database) }
                }
            }
        } message: { prompt in
            switch prompt {
            case .run:
                Text("Coolify runs this backup once, with the storage it already uses. Its schedule stays as it is.")
            case .delete:
                Text("Coolify deletes the schedule and its run history. Dumps already stored stay where they are.")
            }
        }
    }

    private var addButton: some View {
        HStack {
            Spacer()
            restoreButton
            Button("Add Schedule", systemImage: "plus") {
                editor = BackupScheduleTarget(backup: nil)
            }
            .glassButton()
            .disabled(client == nil)
            .help("Add a scheduled backup")
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if model.isLoading, !model.hasLoaded {
            Kindling(caption: "Loading backups…")
        } else if model.hasLoaded, model.backups.isEmpty {
            ContentUnavailableView {
                Label("No backups set up", systemImage: "externaldrive")
            } description: {
                Text(
                    "Add a schedule for \(resourceName). Not every database engine can be backed up."
                )
            } actions: {
                Button("Add Schedule", systemImage: "plus") {
                    editor = BackupScheduleTarget(backup: nil)
                }
                .glassButton(prominent: true)
                .disabled(client == nil)
                restoreButton
            }
        }
    }

    private var restoreButton: some View {
        Button("Restore…", systemImage: "arrow.counterclockwise") {
            restore = RestoreSheetTarget(runID: nil)
        }
        .glassButton()
        .disabled(client == nil)
        .help("Restore a backup into \(resourceName)")
    }

    private var promptTitle: String {
        switch prompt {
        case .run(let backup):
            "Back up \(backup.databaseNames ?? resourceName) now?"
        case .delete(let backup):
            "Delete the schedule for \(backup.databaseNames ?? resourceName)?"
        case nil:
            ""
        }
    }

    private func followHistory() async {
        guard let client else { return }
        while !Task.isCancelled {
            await model.refresh(client: client, database: database)
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
        }
    }
}

private enum BackupPrompt {
    case run(DatabaseBackup)
    case delete(DatabaseBackup)
}

/// The restore sheet, opened on its own or on one run.
private struct RestoreSheetTarget: Identifiable {
    var runID: String?
    var id: String { runID ?? "restore" }
}

private struct BackupScheduleTarget: Identifiable {
    var backup: DatabaseBackup?
    var id: String { backup?.id ?? "new" }
}

#Preview {
    BackupsView(
        client: nil, database: "preview", resourceName: "Postgres", databaseType: "standalone-postgresql",
        status: "running:healthy"
    )
    .frame(width: 560, height: 420)
}

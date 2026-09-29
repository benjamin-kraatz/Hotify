import CoolifyAPI
import SwiftUI

/// Existing backup schedules, execution details, and a manual backup action.
struct BackupsView: View {
    var client: CoolifyClient?
    var database: String
    var resourceName: String
    @State private var model = BackupsModel()
    @State private var candidate: DatabaseBackup?

    var body: some View {
        List {
            if let error = model.error { NoticeBanner(message: error) }
            if let notice = model.notice { Text(notice).font(.callout) }
            ForEach(model.backups) { backup in
                Section {
                    LabeledContent("Schedule", value: backup.enabled ? (backup.frequency ?? "Unknown") : "Disabled")
                    if let databases = backup.databasesToBackup, !databases.isEmpty {
                        LabeledContent("Databases", value: databases)
                    }
                    Button("Back up now", systemImage: "externaldrive.badge.plus") { candidate = backup }
                        .disabled(client == nil || model.isBusy(backup) || backup.id.isEmpty)
                    ForEach(
                        backup.executions.sorted {
                            ($0.createdAtDate ?? .distantPast) > ($1.createdAtDate ?? .distantPast)
                        }
                    ) { execution in
                        BackupExecutionRow(execution: execution)
                    }
                    if backup.executions.isEmpty { Text("No executions yet").foregroundStyle(.secondary) }
                } header: {
                    Text(backup.databasesToBackup ?? "Database backup")
                }
            }
        }
        .overlay {
            if model.isLoading, !model.hasLoaded {
                ProgressView()
            } else if model.hasLoaded, model.backups.isEmpty {
                ContentUnavailableView(
                    "No backup configurations", systemImage: "externaldrive",
                    description: Text(
                        "Configure a backup for this database in Coolify first. Some database engines do not support scheduled backups."
                    ))
            }
        }
        .refreshable { if let client { await model.refresh(client: client, database: database) } }
        .task(id: database) { await followHistory() }
        .confirmationDialog(
            "Back up \(resourceName) now?",
            isPresented: Binding(get: { candidate != nil }, set: { if !$0 { candidate = nil } }),
            titleVisibility: .visible, presenting: candidate
        ) { backup in
            Button("Back up now") {
                guard let client else { return }
                Task { await model.run(backup, client: client, database: database) }
            }
        } message: { _ in
            Text("Uses the selected backup configuration. Its schedule stays unchanged.")
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

#Preview {
    BackupsView(client: nil, database: "preview", resourceName: "Postgres")
}

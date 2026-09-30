import CoolifyAPI
import SwiftUI

/// A database's backup configurations with their run history, and a way to run one now.
struct BackupsView: View {
    var client: CoolifyClient?
    var database: String
    var resourceName: String
    @State private var model = BackupsModel()
    @State private var candidate: DatabaseBackup?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let error = model.error {
                    NoticeBanner(message: error)
                }
                ForEach(model.backups) { backup in
                    BackupCard(
                        backup: backup,
                        fallbackName: resourceName,
                        pendingSince: model.pendingSince(backup),
                        isBusy: model.isBusy(backup),
                        canRun: client != nil && !backup.id.isEmpty,
                        onRun: { candidate = backup }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            if model.isLoading, !model.hasLoaded {
                ProgressView()
            } else if model.hasLoaded, model.backups.isEmpty {
                ContentUnavailableView(
                    "No backups set up",
                    systemImage: "externaldrive",
                    description: Text(
                        "Add a scheduled backup to \(resourceName) in Coolify and its runs show up here. Not every database engine can be backed up."
                    )
                )
            }
        }
        .animation(.snappy, value: model.error)
        .refreshable { if let client { await model.refresh(client: client, database: database) } }
        .task(id: database) { await followHistory() }
        .confirmationDialog(
            "Back up \(candidate?.databaseNames ?? resourceName) now?",
            isPresented: Binding(get: { candidate != nil }, set: { if !$0 { candidate = nil } }),
            titleVisibility: .visible,
            presenting: candidate
        ) { backup in
            Button("Back Up Now") {
                guard let client else { return }
                Task { await model.run(backup, client: client, database: database) }
            }
        } message: { _ in
            Text("Coolify runs this backup once, with the storage it already uses. Its schedule stays as it is.")
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
        .frame(width: 560, height: 420)
}

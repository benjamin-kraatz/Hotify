import CoolifyAPI
import SwiftUI

/// A resource's Storage tab: its volumes and file mounts, and a backup schedule for a volume or a directory.
struct StorageList: View {
    var client: CoolifyClient?
    var route: ResourceRoute
    var resourceName: String
    @State private var model: StorageModel
    @State private var editor: StorageTarget?
    @State private var deleting: ResourceStorage?

    init(client: CoolifyClient?, route: ResourceRoute, resourceName: String, model: StorageModel? = nil) {
        self.client = client
        self.route = route
        self.resourceName = resourceName
        // A default argument is nonisolated, and StorageModel is created on the main actor.
        _model = State(initialValue: model ?? StorageModel())
    }

    private var owner: StorageOwner { StorageOwner(route: route) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                addMenu
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if let error = model.error {
                    NoticeBanner(message: error)
                }
                if let notice = model.notice {
                    Label(notice, systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.ember)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(model.storages) { storage in
                    storageRow(storage)
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
            } else if model.hasLoaded, model.storages.isEmpty, model.error == nil {
                ContentUnavailableView {
                    Label("No storage", systemImage: "externaldrive")
                } description: {
                    Text("Add a persistent volume or a file mount to \(resourceName).")
                } actions: {
                    addMenu
                }
            }
        }
        .animation(.snappy, value: model.error)
        .animation(.snappy, value: model.notice)
        .refreshable { await reload() }
        .task(id: route) { await reload() }
        .sheet(item: $editor) { target in
            editorSheet(target)
        }
        .confirmationDialog(
            "Delete this storage?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { storage in
            Button("Delete", role: .destructive) {
                guard let client else { return }
                Task { await model.delete(storage, client: client, owner: owner) }
            }
        } message: { _ in
            Text("Coolify removes that storage from \(resourceName).")
        }
    }

    private var addMenu: some View {
        Menu {
            Button("Persistent Volume", systemImage: "externaldrive") {
                editor = StorageTarget(kind: .persistent, original: nil)
            }
            Button("File Mount", systemImage: "doc") {
                editor = StorageTarget(kind: .file, original: nil)
            }
        } label: {
            Label("Add", systemImage: "plus")
        }
    }

    private func storageRow(_ storage: ResourceStorage) -> some View {
        Button {
            editor = StorageTarget(kind: storage.kind, original: storage)
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: storage.kind == .persistent ? "externaldrive.fill" : "doc.fill")
                    .font(.title3)
                    .foregroundStyle(.ember)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(storage.listTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(storage.mountPath)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if storage.canScheduleBackup {
                        Text(scheduleLabel(for: storage))
                            .font(.caption)
                            .foregroundStyle(.core)
                    }
                }
                Spacer(minLength: 8)
                Text(storage.kindLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.core)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ember.opacity(0.12), in: .capsule)
            }
            .padding(14)
            .background(.fill.quaternary, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button("Delete", role: .destructive) { deleting = storage }
        }
        .contextMenu {
            Button("Edit") { editor = StorageTarget(kind: storage.kind, original: storage) }
            Button("Delete", role: .destructive) { deleting = storage }
        }
    }

    private func editorSheet(_ target: StorageTarget) -> some View {
        let original = target.original
        let schedule = original.flatMap { model.schedule(for: $0) }
        return StorageEditor(
            original: original,
            kind: target.kind,
            resourceName: resourceName,
            schedule: schedule,
            stores: model.s3Stores,
            didLoadStores: model.didLoadStores,
            isLoadingStores: model.isLoadingStores,
            storesError: model.storesError,
            onSave: { draft in
                guard let client else { return }
                if original == nil {
                    try await model.create(draft, client: client, owner: owner)
                } else {
                    try await model.update(draft, client: client, owner: owner)
                }
            },
            onDelete: client == nil || original == nil
                ? nil
                : {
                    guard let client, let original else { return false }
                    return await model.delete(original, client: client, owner: owner)
                },
            onLoadStores: {
                guard let client else { return }
                await model.loadStores(client: client)
            },
            onSaveSchedule: { request in
                guard let client, let original else { return }
                try await model.saveSchedule(request, storage: original, client: client, owner: owner)
            },
            onDeleteSchedule: {
                guard let client, let original else { return }
                try await model.deleteSchedule(storage: original, client: client, owner: owner)
            },
            onRunSchedule: {
                guard let client, let original else { return }
                try await model.runBackup(storage: original, client: client, owner: owner)
            }
        )
    }

    private func scheduleLabel(for storage: ResourceStorage) -> String {
        guard let frequency = model.schedule(for: storage)?.frequency, !frequency.isEmpty else {
            return "No schedule"
        }
        return BackupFrequencyLabel.title(frequency)
    }

    private func reload() async {
        guard let client else { return }
        await model.load(client: client, owner: owner)
    }
}

/// The mount the editor sheet is adding or changing.
private struct StorageTarget: Identifiable {
    var kind: ResourceStorageKind
    var original: ResourceStorage?

    var id: String { original?.uuid ?? "new-\(kind.rawValue)" }
}

extension ResourceStorage {
    /// The volume name when Coolify stored one, otherwise the mount path.
    var listTitle: String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return mountPath
    }

    var kindLabel: String {
        switch kind {
        case .persistent: "Volume"
        case .file: isDirectory ? "Directory" : "File"
        }
    }
}

/// How a stored frequency reads in the list.
private enum BackupFrequencyLabel {
    static func title(_ frequency: String) -> String {
        switch frequency.lowercased() {
        case "hourly": "Hourly"
        case "daily": "Daily"
        case "weekly": "Weekly"
        case "monthly": "Monthly"
        case "yearly": "Yearly"
        default: frequency
        }
    }
}

#Preview("Volumes") {
    let model = StorageModel()
    model.storages = [
        ResourceStorage(uuid: "vol", kind: .persistent, name: "data", mountPath: "/var/lib/data"),
        ResourceStorage(
            uuid: "dir", kind: .file, mountPath: "/mnt/config", isDirectory: true, fsPath: "/data/config",
            backup: VolumeBackupSchedule(uuid: "bak", frequency: "daily")),
        ResourceStorage(
            uuid: "file", kind: .file, name: "Caddyfile", mountPath: "/etc/caddy/Caddyfile", content: "example.com"),
    ]
    model.schedules = ["vol": VolumeBackupSchedule(uuid: "bak-vol", frequency: "0 2 * * *")]
    model.hasLoaded = true
    return StorageList(client: nil, route: .application("app"), resourceName: "marketing-site", model: model)
        .frame(width: 560, height: 480)
}

#Preview("Empty") {
    let model = StorageModel()
    model.hasLoaded = true
    return StorageList(client: nil, route: .database("db"), resourceName: "postgres", model: model)
        .frame(width: 560, height: 420)
}

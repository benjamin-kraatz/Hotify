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
            VStack(alignment: .leading, spacing: 12) {
                if !model.storages.isEmpty {
                    listHeader
                }
                if let error = model.error {
                    NoticeBanner(message: error)
                }
                if let notice = model.notice {
                    NoticeBanner(message: notice, tone: .done)
                }
                ForEach(model.storages) { storage in
                    StorageRow(storage: storage, schedule: scheduleLabel(for: storage)) {
                        editor = StorageTarget(kind: storage.kind, original: storage)
                    } onDelete: {
                        deleting = storage
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            if model.isLoading, !model.hasLoaded {
                Kindling(caption: "Loading storage…")
            } else if model.hasLoaded, model.storages.isEmpty, model.error == nil {
                ContentUnavailableView {
                    Label("No storage", systemImage: "externaldrive")
                } description: {
                    Text("Add a persistent volume or a file mount to \(resourceName).")
                } actions: {
                    addMenu
                        .glassButton(prominent: true)
                }
            }
        }
        .animation(.snappy, value: model.error)
        .animation(.snappy, value: model.notice)
        .animation(.snappy, value: model.storages.map(\.id))
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
            Label("Add Storage", systemImage: "plus")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add a persistent volume or a file mount")
    }

    private var listHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(storageSummary)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            Spacer()
            addMenu
                .glassButton()
                .disabled(client == nil)
        }
    }

    private var storageSummary: String {
        let volumes = model.storages.count { $0.kind == .persistent }
        let files = model.storages.count - volumes
        var parts: [String] = []
        if volumes > 0 { parts.append(volumes == 1 ? "1 volume" : "\(volumes) volumes") }
        if files > 0 { parts.append(files == 1 ? "1 file mount" : "\(files) file mounts") }
        return parts.joined(separator: " · ")
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

    /// `nil` when the mount has no backup schedule.
    private func scheduleLabel(for storage: ResourceStorage) -> String? {
        guard let frequency = model.schedule(for: storage)?.frequency, !frequency.isEmpty else {
            return nil
        }
        return BackupFrequencyLabel.title(frequency)
    }

    private func reload() async {
        guard let client else { return }
        await model.load(client: client, owner: owner)
    }
}

/// One volume or file mount: what it is, where it mounts, and whether a backup runs on a schedule. Opens the editor.
private struct StorageRow: View {
    var storage: ResourceStorage
    /// The backup frequency. `nil` when nothing is scheduled.
    var schedule: String?
    var onEdit: () -> Void
    var onDelete: () -> Void

    @State private var isHovered = false

    private var symbol: String {
        switch storage.kind {
        case .persistent: "externaldrive.fill"
        case .file: storage.isDirectory ? "folder.fill" : "doc.text.fill"
        }
    }

    private var hostPath: String? {
        guard let path = storage.fsPath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return nil
        }
        return path
    }

    var body: some View {
        Button(action: onEdit) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.ember)
                    .frame(width: 36, height: 36)
                    .background(.ember.opacity(0.12), in: .rect(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(storage.listTitle)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Chip(text: storage.kindLabel)
                    }
                    pathLine
                    if storage.canScheduleBackup {
                        backupLine
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .offset(x: isHovered ? 2 : 0)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .well()
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.ember.opacity(isHovered ? 0.35 : 0), lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.18), value: isHovered)
        .contextMenu {
            Button("Edit…", systemImage: "pencil", action: onEdit)
            Button("Delete…", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .accessibilityHint("Edits this storage")
    }

    /// The path inside the container, after the host path a directory mount reads from.
    private var pathLine: some View {
        HStack(spacing: 5) {
            if let hostPath, storage.kind == .file, storage.isDirectory {
                Text(hostPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "arrow.right")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
            }
            Text(storage.mountPath)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.subheadline.monospaced())
        .foregroundStyle(.secondary)
    }

    private var backupLine: some View {
        Label(
            schedule.map { $0.contains(" ") ? "Backs up on \($0)" : "Backs up \($0.lowercased())" }
                ?? "No backup schedule",
            systemImage: schedule == nil ? "clock.badge.questionmark" : "clock.arrow.circlepath"
        )
        .font(.caption.weight(.medium))
        .foregroundStyle(schedule == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.core))
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

import CoolifyAPI
import SwiftUI

/// Adds a persistent volume or a file mount, or edits one. A saved volume or directory also sets its backup here.
struct StorageEditor: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss

    var original: ResourceStorage?
    var kind: ResourceStorageKind
    var resourceName: String
    var schedule: VolumeBackupSchedule?
    var stores: [S3Storage]
    var didLoadStores: Bool
    var isLoadingStores: Bool
    var storesError: String?
    var onSave: (ResourceStorageDraft) async throws -> Void
    var onDelete: (() async -> Bool)?
    var onLoadStores: () async -> Void
    var onSaveSchedule: (VolumeBackupScheduleRequest) async throws -> Void
    var onDeleteSchedule: () async throws -> Void
    var onRunSchedule: () async throws -> Void

    @State private var name: String
    @State private var mountPath: String
    @State private var isDirectory: Bool
    @State private var fsPath: String
    @State private var content: String
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var confirmDelete = false
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case name
        case mountPath
        case fsPath
        case content
    }

    init(
        original: ResourceStorage?,
        kind: ResourceStorageKind,
        resourceName: String,
        schedule: VolumeBackupSchedule? = nil,
        stores: [S3Storage] = [],
        didLoadStores: Bool = false,
        isLoadingStores: Bool = false,
        storesError: String? = nil,
        onSave: @escaping (ResourceStorageDraft) async throws -> Void,
        onDelete: (() async -> Bool)? = nil,
        onLoadStores: @escaping () async -> Void = {},
        onSaveSchedule: @escaping (VolumeBackupScheduleRequest) async throws -> Void = { _ in },
        onDeleteSchedule: @escaping () async throws -> Void = {},
        onRunSchedule: @escaping () async throws -> Void = {}
    ) {
        self.original = original
        self.kind = kind
        self.resourceName = resourceName
        self.schedule = schedule
        self.stores = stores
        self.didLoadStores = didLoadStores
        self.isLoadingStores = isLoadingStores
        self.storesError = storesError
        self.onSave = onSave
        self.onDelete = onDelete
        self.onLoadStores = onLoadStores
        self.onSaveSchedule = onSaveSchedule
        self.onDeleteSchedule = onDeleteSchedule
        self.onRunSchedule = onRunSchedule
        _name = State(initialValue: original?.name ?? "")
        _mountPath = State(initialValue: original?.mountPath ?? "")
        _isDirectory = State(initialValue: original?.isDirectory ?? false)
        _fsPath = State(initialValue: original?.fsPath ?? "")
        _content = State(initialValue: original?.content ?? "")
    }

    private var isNew: Bool { original == nil }

    private var trimmedMount: String {
        mountPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedHost: String {
        fsPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var problem: String? {
        if kind == .persistent, trimmedName.isEmpty, !trimmedMount.isEmpty {
            return "A volume needs a name."
        }
        if kind == .file, isDirectory, trimmedHost.isEmpty, !trimmedMount.isEmpty {
            return "A directory mount needs a path on the host."
        }
        return nil
    }

    private var canSave: Bool {
        guard !isSaving, problem == nil, !trimmedMount.isEmpty else { return false }
        if kind == .persistent, trimmedName.isEmpty { return false }
        if kind == .file, isDirectory, trimmedHost.isEmpty { return false }
        return isDirty
    }

    private var isDirty: Bool {
        guard let original else { return true }
        if trimmedMount != original.mountPath { return true }
        if kind == .persistent, trimmedName != (original.name ?? "") { return true }
        if kind == .file, !isDirectory, content != (original.content ?? "") { return true }
        return false
    }

    private var title: String {
        switch (isNew, kind, isDirectory) {
        case (true, .persistent, _): "New Volume"
        case (true, .file, true): "New Directory"
        case (true, .file, false): "New File"
        case (false, .persistent, _): "Volume"
        case (false, .file, true): "Directory"
        case (false, .file, false): "File"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                details
                if original?.canScheduleBackup == true {
                    VolumeBackupSection(
                        resourceName: resourceName,
                        schedule: schedule,
                        stores: stores,
                        didLoadStores: didLoadStores,
                        isLoadingStores: isLoadingStores,
                        storesError: storesError,
                        onLoadStores: onLoadStores,
                        onSave: onSaveSchedule,
                        onDelete: onDeleteSchedule,
                        onRun: onRunSchedule
                    )
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
            .confirmationDialog(
                "Delete this storage?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { Task { await delete() } }
            } message: {
                Text("Coolify removes that storage from \(resourceName).")
            }
        }
    }

    @ViewBuilder
    private var details: some View {
        Section {
            if kind == .persistent {
                TextField("Volume name", text: $name, prompt: Text("data"))
                    .autocorrectionDisabled()
                    .focused($focus, equals: .name)
                    #if os(iOS)
                .textInputAutocapitalization(.never)
                    #endif
            }
            TextField("Mount path", text: $mountPath, prompt: Text(verbatim: "/var/lib/data"))
                .font(.body.monospaced())
                .autocorrectionDisabled()
                .focused($focus, equals: .mountPath)
                #if os(iOS)
            .textInputAutocapitalization(.never)
                #endif
            if kind == .file {
                if isNew {
                    Toggle("Directory", isOn: $isDirectory)
                }
                if isDirectory {
                    if isNew {
                        TextField("Host path", text: $fsPath, prompt: Text(verbatim: "/data/config"))
                            .font(.body.monospaced())
                            .autocorrectionDisabled()
                            .focused($focus, equals: .fsPath)
                            #if os(iOS)
                        .textInputAutocapitalization(.never)
                            #endif
                    } else if let fsPath = original?.fsPath, !fsPath.isEmpty {
                        LabeledContent("Host path") {
                            Text(fsPath)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                } else {
                    TextField("Content", text: $content, prompt: Text("File contents"), axis: .vertical)
                        .font(.body.monospaced())
                        .lineLimit(4...12)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .content)
                        #if os(iOS)
                    .textInputAutocapitalization(.never)
                        #endif
                }
            }
        } header: {
            Text(kind == .persistent ? "Volume" : "File mount")
        } footer: {
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.glow)
            } else if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.glow)
            } else if isNew, kind == .persistent || isDirectory {
                Text("You can schedule a backup after this is saved.")
            } else if !isNew, kind == .file, isDirectory {
                Text("Coolify keeps the host path. The mount path is what the container sees.")
            }
        }

        if onDelete != nil {
            Section {
                Button("Delete Storage", role: .destructive) { confirmDelete = true }
                    .disabled(isSaving)
            }
        }
    }

    /// A new empty file omits `content`. Clearing an existing file sends an empty string, which Coolify stores.
    private var fileContent: String? {
        guard kind == .file, !isDirectory else { return nil }
        if content.isEmpty { return isNew ? nil : "" }
        return content
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        let draft = ResourceStorageDraft(
            uuid: original?.uuid,
            type: kind,
            name: kind == .persistent ? trimmedName : nil,
            mountPath: trimmedMount,
            content: fileContent,
            isDirectory: kind == .file && isNew ? isDirectory : nil,
            fsPath: kind == .file && isNew && isDirectory ? trimmedHost : nil
        )
        do {
            try await onSave(draft)
            saveError = nil
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            saveError = (error as? CoolifyError)?.message ?? error.localizedDescription
        }
    }

    private func delete() async {
        guard let onDelete else { return }
        isSaving = true
        defer { isSaving = false }
        if await onDelete() {
            dismiss()
        }
    }
}

#Preview("New volume") {
    StorageEditor(original: nil, kind: .persistent, resourceName: "marketing-site") { _ in }
}

#Preview("Directory") {
    StorageEditor(
        original: ResourceStorage(
            uuid: "dir",
            kind: .file,
            mountPath: "/mnt/config",
            isDirectory: true,
            fsPath: "/data/config",
            backup: VolumeBackupSchedule(uuid: "bak", frequency: "weekly", enabled: true)
        ),
        kind: .file,
        resourceName: "marketing-site",
        schedule: VolumeBackupSchedule(uuid: "bak", frequency: "weekly", enabled: true)
    ) { _ in }
}

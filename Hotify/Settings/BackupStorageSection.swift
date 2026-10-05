import CoolifyAPI
import SwiftUI

/// The team's S3-compatible backup stores for the selected instance.
struct BackupStorageSection: View {
    /// When set, the section shows these stores and does not touch the network or the Keychain.
    var previewStores: [S3Storage]?

    @SwiftUI.Environment(InstanceStore.self) private var store
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: BackupStorageModel
    @State private var editing: StorageEditorTarget?
    @State private var deleting: S3Storage?

    init(previewStores: [S3Storage]? = nil) {
        self.previewStores = previewStores
        let model = BackupStorageModel()
        if let previewStores {
            model.stores = previewStores
            model.hasLoaded = true
        }
        _model = State(initialValue: model)
        _editing = State(initialValue: nil)
        _deleting = State(initialValue: nil)
    }

    var body: some View {
        Section {
            if let message = statusMessage {
                Text(message)
                    .foregroundStyle(.secondary)
            } else if model.isLoading, !model.hasLoaded {
                ProgressView()
            } else {
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.glow)
                        .textSelection(.enabled)
                }
                if let notice = model.notice {
                    Label(
                        notice,
                        systemImage: model.noticeIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                    )
                    .foregroundStyle(model.noticeIsError ? AnyShapeStyle(.glow) : AnyShapeStyle(.secondary))
                }
                if model.stores.isEmpty {
                    Text("No S3 stores yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.stores) { storage in
                    storageRow(storage)
                }
                Button("Add Storage", systemImage: "plus") {
                    editing = StorageEditorTarget(storage: nil)
                }
            }
        } header: {
            Text("Backup Storage")
        } footer: {
            Text(footer)
        }
        .task(id: store.selected?.id) {
            guard previewStores == nil, store.selected != nil else { return }
            await reload()
        }
        .sheet(item: $editing) { target in
            BackupStorageEditor(storage: target.storage) { draft in
                try await create(draft)
            } onUpdate: { update in
                guard let storage = target.storage else { return }
                try await modify(storage, update)
            }
        }
        .confirmationDialog(
            deleting.map { "Delete \($0.name)?" } ?? "",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { storage in
            Button("Delete", role: .destructive) {
                Task { await remove(storage) }
            }
        } message: { _ in
            Text("Backups that copy to this store stop reaching it. Dumps already in the bucket stay there.")
        }
        .animation(reduceMotion ? nil : .snappy, value: model.stores.map(\.id))
        .animation(reduceMotion ? nil : .snappy, value: model.notice)
        .animation(reduceMotion ? nil : .snappy, value: model.error)
    }

    private var statusMessage: String? {
        if previewStores != nil { return nil }
        if store.instances.isEmpty {
            return "Add an instance to manage its backup storage."
        }
        if store.selected == nil {
            return "Select an instance to manage its backup storage."
        }
        return model.unavailable
    }

    private var footer: String {
        if let name = store.selected?.name, previewStores == nil {
            return "S3-compatible stores belong to the team on \(name). A database backup can copy its dumps to one."
        }
        return "S3-compatible stores belong to the team. A database backup can copy its dumps to one."
    }

    private func storageRow(_ storage: S3Storage) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(storage.name)
                    if !storage.isUsable {
                        Text("Not usable")
                            .font(.caption)
                            .foregroundStyle(.glow)
                    }
                }
                Text("\(storage.bucket) · \(storage.region)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(storage.endpoint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let description = storage.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if model.validatingID == storage.id {
                ProgressView()
                    .controlSize(.small)
            }
            Menu {
                Button("Validate", systemImage: "checkmark.shield") {
                    Task { await validate(storage) }
                }
                Button("Edit", systemImage: "pencil") {
                    editing = StorageEditorTarget(storage: storage)
                }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    deleting = storage
                }
            } label: {
                Label("Store actions", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func reload() async {
        model.unavailable = nil
        do {
            let client = try connectedClient()
            await model.load(client)
        } catch is CancellationError {
            return
        } catch {
            model.stores = []
            model.hasLoaded = true
            model.isLoading = false
            model.unavailable = (error as? CoolifyError)?.message ?? error.localizedDescription
        }
    }

    private func create(_ draft: S3StorageDraft) async throws {
        if previewStores != nil {
            model.stores.append(
                S3Storage(
                    uuid: UUID().uuidString,
                    name: draft.name,
                    description: draft.description,
                    endpoint: draft.endpoint,
                    bucket: draft.bucket,
                    region: draft.region,
                    isUsable: draft.isUsable ?? true
                )
            )
            return
        }
        let client = try connectedClient()
        _ = try await client.createS3Storage(draft)
        await model.load(client)
    }

    private func modify(_ storage: S3Storage, _ update: S3StorageUpdate) async throws {
        if previewStores != nil {
            guard let index = model.stores.firstIndex(where: { $0.id == storage.id }) else { return }
            model.stores[index] = S3Storage(
                uuid: storage.uuid,
                name: update.name ?? storage.name,
                description: update.description ?? storage.description,
                endpoint: update.endpoint ?? storage.endpoint,
                bucket: update.bucket ?? storage.bucket,
                region: update.region ?? storage.region,
                isUsable: update.isUsable ?? storage.isUsable
            )
            return
        }
        let client = try connectedClient()
        _ = try await client.updateS3Storage(storage.id, update)
        await model.load(client)
    }

    private func remove(_ storage: S3Storage) async {
        if previewStores != nil {
            model.stores.removeAll { $0.id == storage.id }
            return
        }
        do {
            let client = try connectedClient()
            _ = try await client.deleteS3Storage(storage.id)
            model.notice = nil
            await model.load(client)
        } catch is CancellationError {
            return
        } catch {
            model.error = (error as? CoolifyError)?.summary ?? error.localizedDescription
        }
    }

    private func validate(_ storage: S3Storage) async {
        if previewStores != nil {
            model.notice = "Preview stores are not checked."
            model.noticeIsError = false
            return
        }
        model.validatingID = storage.id
        defer { model.validatingID = nil }
        do {
            let client = try connectedClient()
            let result = try await client.validateS3Storage(storage.id)
            let fallback = result.valid ? "The store answered." : "The store could not be reached."
            model.notice = result.message ?? fallback
            model.noticeIsError = !result.valid
        } catch is CancellationError {
            return
        } catch {
            model.notice = (error as? CoolifyError)?.summary ?? error.localizedDescription
            model.noticeIsError = true
        }
    }

    /// The selected instance's client. A missing token is reported without logging it.
    private func connectedClient() throws -> CoolifyClient {
        guard let instance = store.selected else {
            throw CoolifyError(message: "Select an instance to manage its backup storage.")
        }
        #if DEBUG
        if let fixture = store.fixtureClients[instance.id] {
            return fixture
        }
        #endif
        guard let token = TokenStore.load(for: instance.id), !token.isEmpty else {
            throw CoolifyError(message: "\(instance.name) has no API token on this device.")
        }
        return try CoolifyClient(instanceURL: instance.baseURL, token: token)
    }
}

private struct StorageEditorTarget: Identifiable {
    var storage: S3Storage?
    var id: String { storage?.id ?? "new" }
}

@Observable
private final class BackupStorageModel {
    var stores: [S3Storage] = []
    var error: String?
    var notice: String?
    var noticeIsError = false
    var unavailable: String?
    var hasLoaded = false
    var isLoading = false
    var validatingID: String?

    func load(_ client: CoolifyClient) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await client.s3Storages()
            try Task.checkCancellation()
            stores = loaded
            hasLoaded = true
            unavailable = nil
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = (error as? CoolifyError)?.summary ?? error.localizedDescription
        }
    }
}

#Preview("Stores") {
    Form {
        BackupStorageSection(
            previewStores: [
                S3Storage(
                    uuid: "store-1",
                    name: "Backups",
                    description: "Nightly dumps",
                    endpoint: "https://s3.example.com",
                    bucket: "dumps",
                    region: "us-east-1",
                    isUsable: true
                ),
                S3Storage(
                    uuid: "store-2",
                    name: "Archive",
                    endpoint: "https://minio.example.com",
                    bucket: "archive",
                    region: "eu-central-1",
                    isUsable: false
                ),
            ]
        )
    }
    .formStyle(.grouped)
    .environment(InstanceStore(instances: []))
    .frame(width: 500, height: 420)
}

#Preview("No instance") {
    Form {
        BackupStorageSection()
    }
    .formStyle(.grouped)
    .environment(InstanceStore(instances: []))
    .frame(width: 500, height: 240)
}

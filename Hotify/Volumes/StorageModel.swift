import CoolifyAPI
import Foundation

extension StorageOwner {
    init(route: ResourceRoute) {
        switch route {
        case .application(let uuid): self = .application(uuid)
        case .database(let uuid): self = .database(uuid)
        case .service(let uuid): self = .service(uuid)
        }
    }
}

/// Loads a resource's mounts and keeps the volume backup schedule from the last save.
///
/// Coolify 4.3 has no documented GET for a volume backup schedule. A schedule nested on a storage is used when the
/// list includes one. Otherwise the schedule returned by the last PUT in this session is what the form shows.
@MainActor
@Observable
final class StorageModel {
    var storages: [ResourceStorage] = []
    var schedules: [String: VolumeBackupSchedule] = []
    var s3Stores: [S3Storage] = []
    var error: String?
    var notice: String?
    var storesError: String?
    var hasLoaded = false
    var didLoadStores = false
    var isLoading = false
    var isLoadingStores = false

    private static var remembered: [String: [String: VolumeBackupSchedule]] = [:]

    func schedule(for storage: ResourceStorage) -> VolumeBackupSchedule? {
        schedules[storage.uuid] ?? storage.backup
    }

    func load(client: CoolifyClient, owner: StorageOwner) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await client.storages(of: owner)
            try Task.checkCancellation()
            let key = memoryKey(client: client, owner: owner)
            var kept = Self.remembered[key] ?? [:]
            for storage in loaded {
                if let backup = storage.backup {
                    kept[storage.uuid] = backup
                }
            }
            storages = loaded
            schedules = kept
            Self.remembered[key] = kept
            hasLoaded = true
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = (error as? CoolifyError)?.message ?? error.localizedDescription
        }
    }

    func create(_ draft: ResourceStorageDraft, client: CoolifyClient, owner: StorageOwner) async throws {
        _ = try await client.createStorage(draft, on: owner)
        notice = nil
        await load(client: client, owner: owner)
    }

    func update(_ draft: ResourceStorageDraft, client: CoolifyClient, owner: StorageOwner) async throws {
        _ = try await client.updateStorage(draft, on: owner)
        notice = nil
        await load(client: client, owner: owner)
    }

    @discardableResult
    func delete(_ storage: ResourceStorage, client: CoolifyClient, owner: StorageOwner) async -> Bool {
        do {
            try await client.deleteStorage(storage.uuid, from: owner)
            let key = memoryKey(client: client, owner: owner)
            schedules[storage.uuid] = nil
            Self.remembered[key]?[storage.uuid] = nil
            notice = nil
            error = nil
            await load(client: client, owner: owner)
            return true
        } catch is CancellationError {
            return false
        } catch {
            self.error = (error as? CoolifyError)?.message ?? error.localizedDescription
            return false
        }
    }

    func loadStores(client: CoolifyClient) async {
        guard !isLoadingStores else { return }
        isLoadingStores = true
        defer { isLoadingStores = false }
        do {
            s3Stores = try await client.s3Storages()
            try Task.checkCancellation()
            didLoadStores = true
            storesError = nil
        } catch is CancellationError {
            return
        } catch {
            storesError = (error as? CoolifyError)?.message ?? error.localizedDescription
        }
    }

    func saveSchedule(
        _ request: VolumeBackupScheduleRequest,
        storage: ResourceStorage,
        client: CoolifyClient,
        owner: StorageOwner
    ) async throws {
        let saved = try await client.setVolumeBackup(request, storage: storage.uuid, on: owner)
        keep(saved, storage: storage.uuid, client: client, owner: owner)
        notice = saved.message ?? "Backup schedule saved."
        error = nil
        await load(client: client, owner: owner)
    }

    func deleteSchedule(storage: ResourceStorage, client: CoolifyClient, owner: StorageOwner) async throws {
        try await client.deleteVolumeBackup(storage: storage.uuid, from: owner)
        let key = memoryKey(client: client, owner: owner)
        schedules[storage.uuid] = nil
        Self.remembered[key]?[storage.uuid] = nil
        notice = "Backup schedule deleted."
        error = nil
        await load(client: client, owner: owner)
    }

    func runBackup(storage: ResourceStorage, client: CoolifyClient, owner: StorageOwner) async throws {
        let queued = try await client.runVolumeBackup(storage: storage.uuid, on: owner)
        notice = queued.message ?? "Volume backup queued."
        error = nil
    }

    private func keep(
        _ schedule: VolumeBackupSchedule, storage storageUUID: String, client: CoolifyClient, owner: StorageOwner
    ) {
        let key = memoryKey(client: client, owner: owner)
        var kept = Self.remembered[key] ?? [:]
        kept[storageUUID] = schedule
        Self.remembered[key] = kept
        schedules = kept
    }

    private func memoryKey(client: CoolifyClient, owner: StorageOwner) -> String {
        let ownerKey: String
        switch owner {
        case .application(let uuid): ownerKey = "application:\(uuid)"
        case .database(let uuid): ownerKey = "database:\(uuid)"
        case .service(let uuid): ownerKey = "service:\(uuid)"
        }
        return "\(client.apiBaseURL.absoluteString)|\(ownerKey)"
    }
}

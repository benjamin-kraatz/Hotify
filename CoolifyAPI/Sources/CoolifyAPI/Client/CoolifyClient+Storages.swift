import Foundation

/// The application, database, or service whose volumes and file mounts a request reads or changes.
public enum StorageOwner: Sendable, Hashable {
    case application(String)
    case database(String)
    case service(String)

    var path: String {
        switch self {
        case .application(let uuid): "applications/\(CoolifyURL.encodePathComponent(uuid))/storages"
        case .database(let uuid): "databases/\(CoolifyURL.encodePathComponent(uuid))/storages"
        case .service(let uuid): "services/\(CoolifyURL.encodePathComponent(uuid))/storages"
        }
    }

    func storagePath(_ storageUUID: String) -> String {
        "\(path)/\(CoolifyURL.encodePathComponent(storageUUID))"
    }

    func backupPath(_ storageUUID: String) -> String {
        "\(storagePath(storageUUID))/backups"
    }
}

extension CoolifyClient {
    /// Lists persistent volumes and file mounts.
    ///
    /// Coolify 4.3 returns an object, `{ "persistent_storages": [...], "file_storages": [...] }`, not a bare array.
    /// The item objects are loosely specified. A bare array is accepted when a version sends one instead.
    public func storages(of owner: StorageOwner) async throws -> [ResourceStorage] {
        let catalog: StorageCatalog = try await get(owner.path)
        return catalog.storages
    }

    /// Adds a volume or a file mount. A persistent volume needs `name`. A directory file mount needs `fs_path`.
    public func createStorage(_ draft: ResourceStorageDraft, on owner: StorageOwner) async throws -> ResourceStorage {
        try await post(owner.path, body: draft)
    }

    /// Updates a mount. Coolify finds it by `draft.uuid` in the body, on the collection path, not the item path.
    public func updateStorage(_ draft: ResourceStorageDraft, on owner: StorageOwner) async throws -> ResourceStorage {
        try await patch(owner.path, body: draft)
    }

    /// Removes the mount. Coolify deletes that storage.
    public func deleteStorage(_ storageUUID: String, from owner: StorageOwner) async throws {
        _ = try await acknowledge("DELETE", path: owner.storagePath(storageUUID))
    }

    /// Creates or replaces the volume backup schedule. There is no documented GET; keep this response.
    public func setVolumeBackup(
        _ request: VolumeBackupScheduleRequest,
        storage storageUUID: String,
        on owner: StorageOwner
    ) async throws -> VolumeBackupSchedule {
        try await put(owner.backupPath(storageUUID), body: request)
    }

    /// Deletes the schedule and the local and S3 archives Coolify kept for it.
    public func deleteVolumeBackup(storage storageUUID: String, from owner: StorageOwner) async throws {
        _ = try await acknowledge("DELETE", path: owner.backupPath(storageUUID))
    }

    /// Queues one volume backup for a mount that already has a schedule.
    public func runVolumeBackup(storage storageUUID: String, on owner: StorageOwner) async throws -> QueuedAction {
        try await acknowledge("POST", path: "\(owner.backupPath(storageUUID))/run")
    }
}

/// Coolify 4.3 lists storages as two arrays on an object. A bare array is the fallback.
private struct StorageCatalog: Decodable {
    var storages: [ResourceStorage]

    private enum CodingKeys: String, CodingKey {
        case persistentStorages
        case fileStorages
    }

    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            var list: [ResourceStorage] = []
            while !unkeyed.isAtEnd {
                list.append(try unkeyed.decode(ResourceStorage.self))
            }
            storages = list
            return
        }
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        let persistent = try keyed.decodeIfPresent([ResourceStorage].self, forKey: .persistentStorages) ?? []
        let files = try keyed.decodeIfPresent([ResourceStorage].self, forKey: .fileStorages) ?? []
        storages = persistent.map { $0.withKind(.persistent) } + files.map { $0.withKind(.file) }
    }
}

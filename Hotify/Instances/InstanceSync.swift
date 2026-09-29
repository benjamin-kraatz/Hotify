import Foundation
import Observation

/// Persists instance records locally and merges independent iCloud changes without storing credentials.
@MainActor
@Observable
final class InstanceSync {
    private(set) var errorMessage: String?

    private let defaults: UserDefaults
    private let cloud: NSUbiquitousKeyValueStore
    private let localKey = "hotify.instanceRecords.v1"
    private let prefix = "hotify.instance.v1."
    @ObservationIgnored private var observer: NSObjectProtocol?
    private(set) var records: [UUID: InstanceSyncRecord]
    var onChange: (([InstanceSyncRecord]) -> Void)?

    init(defaults: UserDefaults = .standard, cloud: NSUbiquitousKeyValueStore = .default) {
        self.defaults = defaults
        self.cloud = cloud
        let data = defaults.data(forKey: localKey)
        let saved = data.flatMap { try? JSONDecoder().decode([InstanceSyncRecord].self, from: $0) } ?? []
        records = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { $0.merged(with: $1) })
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { [weak self] notification in
            let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            Task { @MainActor [weak self] in
                // Quota failures are not remote edits. Keep the local copy for a later retry.
                guard reason != NSUbiquitousKeyValueStoreQuotaViolationChange else {
                    self?.errorMessage = "iCloud storage for Hotify is full. Changes are saved on this device."
                    return
                }
                self?.errorMessage = nil
                self?.refresh()
            }
        }
        if !cloud.synchronize() {
            errorMessage = "iCloud sync is unavailable. Changes are saved on this device."
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func save(_ record: InstanceSyncRecord) {
        records[record.id] = records[record.id]?.merged(with: record) ?? record
        refresh()
    }

    func refresh() {
        for (key, value) in cloud.dictionaryRepresentation where key.hasPrefix(prefix) {
            guard let data = value as? Data,
                let remote = try? JSONDecoder().decode(InstanceSyncRecord.self, from: data),
                key == prefix + remote.id.uuidString
            else { continue }
            records[remote.id] = records[remote.id]?.merged(with: remote) ?? remote
        }
        if let data = try? JSONEncoder().encode(Array(records.values)) {
            defaults.set(data, forKey: localKey)
        }
        for record in records.values {
            let key = prefix + record.id.uuidString
            let existing = cloud.data(forKey: key).flatMap {
                try? JSONDecoder().decode(InstanceSyncRecord.self, from: $0)
            }
            if existing != record, let data = try? JSONEncoder().encode(record) {
                cloud.set(data, forKey: key)
            }
        }
        onChange?(Array(records.values))
    }
}

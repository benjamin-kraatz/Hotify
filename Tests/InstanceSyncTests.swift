import Foundation

/// An in-memory cloud store keeps these checks away from a real iCloud account.
final class TestCloudStore: NSUbiquitousKeyValueStore {
    var values: [String: Any] = [:]
    override var dictionaryRepresentation: [String: Any] { values }
    override func data(forKey key: String) -> Data? { values[key] as? Data }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func synchronize() -> Bool { true }
}

@main
struct InstanceSyncTests {
    @MainActor
    static func main() throws {
        let suite = "Hotify.SyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let cloud = TestCloudStore()
        let sync = InstanceSync(defaults: defaults, cloud: cloud)
        let first = InstanceSyncRecord(
            id: UUID(), name: "Home", baseURL: URL(string: "https://example.com")!,
            modifiedAt: Date(timeIntervalSince1970: 100), revision: "a", isDeleted: false
        )
        var second = first
        second.id = UUID()
        second.name = "Work"
        sync.save(first)
        cloud.set(try JSONEncoder().encode(second), forKey: "hotify.instance.v1." + second.id.uuidString)
        sync.refresh()
        precondition(sync.records.count == 2, "Independent additions must survive a merge")

        var edited = first
        edited.name = "Renamed"
        edited.modifiedAt = Date(timeIntervalSince1970: 200)
        cloud.set(try JSONEncoder().encode(edited), forKey: "hotify.instance.v1." + first.id.uuidString)
        sync.refresh()
        precondition(sync.records[first.id] == edited, "Remote edits must replace older metadata")
        sync.save(first)
        precondition(sync.records[first.id] == edited, "Stale local edits must not overwrite newer metadata")

        var concurrent = edited
        concurrent.revision = "b"
        concurrent.name = "Concurrent"
        precondition(edited.merged(with: concurrent) == concurrent.merged(with: edited), "Ties must converge")

        var deleted = first
        deleted.isDeleted = true
        sync.save(deleted)
        cloud.set(try JSONEncoder().encode(edited), forKey: "hotify.instance.v1." + first.id.uuidString)
        sync.refresh()
        precondition(sync.records[first.id]?.isDeleted == true, "Offline edits must not restore deleted instances")
        let restored = InstanceSync(defaults: defaults, cloud: TestCloudStore())
        precondition(restored.records[first.id]?.isDeleted == true, "Tombstones must survive relaunch")
        precondition(restored.records[second.id] == second, "Offline state must survive relaunch")

        cloud.set(Data("invalid".utf8), forKey: "hotify.instance.v1.invalid")
        sync.refresh()
        precondition(sync.records.count == 2, "Malformed records must not discard local state")
        let encoded = String(data: try JSONEncoder().encode(first), encoding: .utf8)!
        precondition(!encoded.contains("token"), "Synced metadata must not include credentials")
        print("Instance sync checks passed")
    }
}

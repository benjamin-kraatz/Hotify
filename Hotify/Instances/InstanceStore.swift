import CoolifyAPI
import Foundation

/// Saved instances. Tokens are stored separately in the Keychain, keyed by instance id.
@MainActor
@Observable
final class InstanceStore {
    private(set) var instances: [CoolifyInstance] = []
    var selectedID: CoolifyInstance.ID?

    #if DEBUG
    var fixtureClients: [UUID: CoolifyClient] = [:]
    #endif

    private var sync: InstanceSync?

    private let defaultsKey = "hotify.instances"

    init() {
        load()
        let sync = InstanceSync()
        self.sync = sync
        sync.onChange = { [weak self] records in self?.apply(records) }
        // Legacy entries have no edit timestamp. Any synced edit or deletion takes precedence.
        for instance in instances where sync.records[instance.id] == nil {
            sync.save(record(for: instance, modifiedAt: .distantPast))
        }
        sync.refresh()
        refreshCredentials()
    }

    init(instances: [CoolifyInstance]) {
        self.instances = instances
        selectedID = instances.first?.id
    }

    var syncError: String? { sync?.errorMessage }

    var selected: CoolifyInstance? {
        instances.first { $0.id == selectedID }
    }

    func client(for instance: CoolifyInstance) -> CoolifyClient? {
        #if DEBUG
        if let fixture = fixtureClients[instance.id] { return fixture }
        #endif
        guard let token = TokenStore.load(for: instance.id) else { return nil }
        return try? CoolifyClient(instanceURL: instance.baseURL, token: token)
    }

    func add(name: String, baseURL: String, token: String) throws -> CoolifyInstance {
        #if DEBUG
        guard fixtureClients.isEmpty else { throw CoolifyError(message: "Fixture instances cannot be edited.") }
        #endif
        let (saved, trimmedToken) = try validated(name: name, baseURL: baseURL, token: token)
        try TokenStore.save(trimmedToken, for: saved.id)
        instances.append(saved)
        sync?.save(record(for: saved))
        selectedID = saved.id
        persist()
        return saved
    }

    /// Saves a new name, URL, and token for an instance that is already in the list.
    ///
    /// Returns whether the URL or token changed. A name-only edit leaves the open dashboard alone.
    @discardableResult
    func update(id: CoolifyInstance.ID, name: String, baseURL: String, token: String) throws -> Bool {
        #if DEBUG
        guard fixtureClients.isEmpty else { throw CoolifyError(message: "Fixture instances cannot be edited.") }
        #endif
        guard let index = instances.firstIndex(where: { $0.id == id }) else {
            throw CoolifyError(message: "That instance is no longer saved.")
        }
        let previous = instances[index]
        let (saved, trimmedToken) = try validated(id: id, name: name, baseURL: baseURL, token: token)
        let tokenChanged = TokenStore.load(for: id) != trimmedToken
        if tokenChanged {
            try TokenStore.save(trimmedToken, for: id)
        }
        instances[index] = saved
        sync?.save(record(for: saved))
        persist()
        return previous.baseURL != saved.baseURL || tokenChanged
    }

    func remove(_ instance: CoolifyInstance) {
        #if DEBUG
        guard fixtureClients.isEmpty else { return }
        #endif
        sync?.save(record(for: instance, isDeleted: true))
        TokenStore.delete(for: instance.id)
        instances.removeAll { $0.id == instance.id }
        if selectedID == instance.id {
            selectedID = instances.first?.id
        }
        persist()
    }

    /// Picks up `COOLIFY_DEMO_INSTANCE_BASE_URL` and `COOLIFY_DEMO_INSTANCE_API_KEY` when the process has them.
    func seedFromEnvironment() {
        guard instances.isEmpty else { return }
        let environment = ProcessInfo.processInfo.environment
        guard let baseURL = environment["COOLIFY_DEMO_INSTANCE_BASE_URL"], !baseURL.isEmpty,
            let token = environment["COOLIFY_DEMO_INSTANCE_API_KEY"], !token.isEmpty
        else { return }
        _ = try? add(name: "Demo", baseURL: baseURL, token: token)
    }

    /// Retries legacy token migration and picks up cloud changes when the app becomes active.
    func refreshSync() {
        sync?.refresh()
        refreshCredentials()
    }

    private func refreshCredentials() {
        guard sync != nil else { return }
        for instance in instances { TokenStore.migrate(for: instance.id) }
    }

    private func record(
        for instance: CoolifyInstance, modifiedAt: Date = .now, isDeleted: Bool = false
    ) -> InstanceSyncRecord {
        InstanceSyncRecord(
            id: instance.id, name: instance.name, baseURL: instance.baseURL,
            modifiedAt: modifiedAt, revision: UUID().uuidString, isDeleted: isDeleted
        )
    }

    private func apply(_ records: [InstanceSyncRecord]) {
        for record in records where record.isDeleted { TokenStore.delete(for: record.id) }
        instances = records.filter { !$0.isDeleted }.map {
            CoolifyInstance(id: $0.id, name: $0.name, baseURL: $0.baseURL)
        }.sorted {
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id.uuidString < $1.id.uuidString
        }
        if !instances.contains(where: { $0.id == selectedID }) {
            selectedID = instances.first?.id
        }
        persist()
    }

    private func validated(id: UUID = UUID(), name: String, baseURL: String, token: String) throws -> (
        CoolifyInstance, String
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let url = URL(string: trimmedURL) else {
            throw CoolifyError(message: "Name and URL are required.")
        }
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try CoolifyClient(instanceURL: url, token: trimmedToken)
        return (CoolifyInstance(id: id, name: trimmedName, baseURL: url), trimmedToken)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode([CoolifyInstance].self, from: data)
        else { return }
        instances = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(instances) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

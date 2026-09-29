import CoolifyAPI
import Foundation

/// Saved instances. Tokens are stored separately in the Keychain, keyed by instance id.
@Observable
final class InstanceStore {
    private(set) var instances: [CoolifyInstance] = []
    var selectedID: CoolifyInstance.ID?

    private let defaultsKey = "hotify.instances"

    init() {
        load()
        if selectedID == nil {
            selectedID = instances.first?.id
        }
    }

    init(instances: [CoolifyInstance]) {
        self.instances = instances
        selectedID = instances.first?.id
    }

    var selected: CoolifyInstance? {
        instances.first { $0.id == selectedID }
    }

    func client(for instance: CoolifyInstance) -> CoolifyClient? {
        guard let token = TokenStore.load(for: instance.id) else { return nil }
        return try? CoolifyClient(instanceURL: instance.baseURL, token: token)
    }

    func add(name: String, baseURL: String, token: String) throws -> CoolifyInstance {
        let (saved, trimmedToken) = try validated(name: name, baseURL: baseURL, token: token)
        try TokenStore.save(trimmedToken, for: saved.id)
        instances.append(saved)
        selectedID = saved.id
        persist()
        return saved
    }

    /// Saves a new name, URL, and token for an instance that is already in the list.
    ///
    /// Returns whether the URL or token changed. A name-only edit leaves the open dashboard alone.
    @discardableResult
    func update(id: CoolifyInstance.ID, name: String, baseURL: String, token: String) throws -> Bool {
        guard let index = instances.firstIndex(where: { $0.id == id }) else {
            throw CoolifyError(message: "That instance is no longer saved.")
        }
        let previous = instances[index]
        let (saved, trimmedToken) = try validated(id: id, name: name, baseURL: baseURL, token: token)
        let tokenChanged = TokenStore.load(for: id) != trimmedToken
        // Rewriting an unchanged token deletes and recreates the Keychain item.
        if tokenChanged {
            try TokenStore.save(trimmedToken, for: id)
        }
        instances[index] = saved
        persist()
        return previous.baseURL != saved.baseURL || tokenChanged
    }

    func remove(_ instance: CoolifyInstance) {
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

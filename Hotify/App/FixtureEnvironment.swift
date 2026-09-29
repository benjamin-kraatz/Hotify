#if DEBUG
import CoolifyAPI
import Foundation

/// Opt-in, loopback-only fixture instances for native UI checks, with no Keychain or iCloud writes.
enum FixtureEnvironment {
    static func makeStore() -> InstanceStore? {
        guard ProcessInfo.processInfo.environment["HOTIFY_FIXTURES"] == "1" else { return nil }
        let instances = [18081, 18082].enumerated().map { index, port in
            CoolifyInstance(
                id: UUID(
                    uuidString: index == 0
                        ? "00000000-0000-0000-0000-000000000001" : "00000000-0000-0000-0000-000000000002")!,
                name: index == 0 ? "Fixture Source" : "Fixture Destination",
                baseURL: URL(string: "http://127.0.0.1:\(port)")!)
        }
        let store = InstanceStore(instances: instances)
        for instance in instances {
            store.fixtureClients[instance.id] = try? instance.client(token: "fixture-only-not-a-secret")
        }
        return store
    }
}
#endif

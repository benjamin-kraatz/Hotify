import CoolifyAPI
import Foundation

/// The SSH address someone typed for a server, in place of the one Coolify reports, keyed by server uuid.
struct AddressOverrides {
    private static let key = "hotify.terminal.addresses"
    var defaults: UserDefaults = .standard

    func address(for server: String) -> SSHAddress? {
        stored[server]
    }

    /// `nil` goes back to Coolify's address.
    func set(_ address: SSHAddress?, for server: String) {
        var addresses = stored
        addresses[server] = address
        if let data = try? JSONEncoder().encode(addresses) {
            defaults.set(data, forKey: Self.key)
        }
    }

    private var stored: [String: SSHAddress] {
        guard let data = defaults.data(forKey: Self.key) else { return [:] }
        return (try? JSONDecoder().decode([String: SSHAddress].self, from: data)) ?? [:]
    }
}

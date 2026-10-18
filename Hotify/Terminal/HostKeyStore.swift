import Foundation
import HotifySSH

/// The host key each server proved itself with the first time, keyed by server uuid. Host keys aren't secret, and the
/// widgets don't use them, so they stay in the app's own defaults.
struct HostKeyStore {
    private static let key = "hotify.terminal.hostKeys"
    var defaults: UserDefaults = .standard

    func key(for server: String) -> SSHHostKey? {
        stored[server].map(SSHHostKey.init(openSSH:))
    }

    func trust(_ hostKey: SSHHostKey, for server: String) {
        var keys = stored
        keys[server] = hostKey.openSSH
        defaults.set(keys, forKey: Self.key)
    }

    private var stored: [String: String] {
        defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }
}

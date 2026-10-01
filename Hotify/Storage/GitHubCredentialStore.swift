import Foundation

/// Keeps the optional GitHub PR-read token separate from instance credentials in the Keychain.
enum GitHubCredentialStore {
    private static let account = UUID(uuidString: "B428BFBD-D4C1-4EAA-B51B-33DCA83F193D")!

    static func load() -> String? { TokenStore.load(for: account) }
    static func save(_ token: String) throws { try TokenStore.save(token, for: account) }
    static func delete() { TokenStore.delete(for: account) }
}

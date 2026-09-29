import Foundation
import Security

/// Keychain storage for instance tokens.
///
/// `kSecUseDataProtectionKeychain` plus `kSecAttrAccessibleAfterFirstUnlock` is what a sandboxed
/// macOS app can read again on the next launch.
enum TokenStore {
    private static let service = "com.sebastiankraatz.Hotify.token"

    static func save(_ token: String, for instanceID: UUID) throws {
        let account = instanceID.uuidString
        let data = Data(token.utf8)
        let base = query(account: account)
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        item[kSecUseDataProtectionKeychain as String] = true
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TokenStoreError(status: status)
        }
    }

    static func load(for instanceID: UUID) -> String? {
        var item = query(account: instanceID.uuidString)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        item[kSecUseDataProtectionKeychain as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(for instanceID: UUID) {
        SecItemDelete(query(account: instanceID.uuidString) as CFDictionary)
    }

    private static func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

struct TokenStoreError: Error, LocalizedError {
    var status: OSStatus
    var errorDescription: String? { "Keychain failed (\(status))." }
}

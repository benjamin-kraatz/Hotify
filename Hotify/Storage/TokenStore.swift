import Foundation
import Security

/// Instance credentials stored in the data protection Keychain and synced by iCloud Keychain.
enum TokenStore {
    private static let service = "com.sebastiankraatz.Hotify.token"

    static func save(_ token: String, for instanceID: UUID) throws {
        let base = query(instanceID, synchronizable: true)
        let data = Data(token.utf8)
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = base
            item[kSecValueData as String] = data
            // This accessibility class permits iCloud sync and background reads after first unlock.
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw TokenStoreError(status: added) }
        } else if status != errSecSuccess {
            throw TokenStoreError(status: status)
        }
        // Keep the old local credential until its synchronizable replacement has been saved.
        SecItemDelete(query(instanceID, synchronizable: false) as CFDictionary)
    }

    static func load(for instanceID: UUID) -> String? {
        read(instanceID, synchronizable: true) ?? read(instanceID, synchronizable: false)
    }

    static func migrate(for instanceID: UUID) {
        if read(instanceID, synchronizable: true) != nil {
            SecItemDelete(query(instanceID, synchronizable: false) as CFDictionary)
        } else if let token = read(instanceID, synchronizable: false) {
            // A locked Keychain can reject migration; leave the original and retry on activation.
            try? save(token, for: instanceID)
        }
    }

    static func delete(for instanceID: UUID) {
        var item = query(instanceID, synchronizable: true)
        item[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        SecItemDelete(item as CFDictionary)
    }

    private static func read(_ instanceID: UUID, synchronizable: Bool) -> String? {
        var item = query(instanceID, synchronizable: synchronizable)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func query(_ instanceID: UUID, synchronizable: Bool) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: instanceID.uuidString,
            kSecAttrSynchronizable as String: synchronizable,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}

struct TokenStoreError: Error, LocalizedError {
    var status: OSStatus
    var errorDescription: String? { "Keychain failed (\(status))." }
}

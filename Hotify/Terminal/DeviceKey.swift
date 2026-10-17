import CryptoKit
import Foundation
import HotifySSH
import LocalAuthentication
import Security

#if os(iOS)
import UIKit
#endif

/// This device's own SSH key, which the terminal signs in with.
///
/// The private key stays in this device's Keychain. It doesn't sync, and it disappears if the passcode is removed.
/// Reading it asks for Face ID, Touch ID, or the passcode every time. The public half isn't secret and is kept
/// beside it, so setup can show it without a prompt.
enum DeviceKey {
    private static let service = "com.sebastiankraatz.Hotify.terminal-key"
    private static let account = "device"
    private static let publicKeyDefaultsKey = "hotify.terminal.devicePublicKey"

    /// The line to add to a server's `authorized_keys`. Makes the key the first time, without a prompt.
    static func publicKeyLine(defaults: UserDefaults = .standard) throws -> String {
        if let line = defaults.string(forKey: publicKeyDefaultsKey), exists() {
            return line
        }
        let key = Curve25519.Signing.PrivateKey()
        try store(key)
        let line = SSHIdentity(ed25519: key).publicKeyLine(comment: comment)
        defaults.set(line, forKey: publicKeyDefaultsKey)
        return line
    }

    /// Asks the owner, then reads the key. Pass `reason` through `reason(_:)`.
    static func unlock(reason: String) async throws -> SSHIdentity {
        let context = try await confirmOwner(reason: reason)
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        // The context the owner just confirmed, so the Keychain doesn't ask a second time.
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data)
            else { throw DeviceKeyError.keychain(status) }
            return SSHIdentity(ed25519: key)
        case errSecItemNotFound:
            throw DeviceKeyError.missing
        case errSecUserCanceled:
            throw DeviceKeyError.cancelled
        default:
            throw DeviceKeyError.keychain(status)
        }
    }

    /// Asks for Face ID, Touch ID, or the passcode, and returns the confirmed context.
    @discardableResult
    static func confirmOwner(reason: String) async throws -> LAContext {
        let context = LAContext()
        // Each session asks on its own, so an unlock from earlier can't carry over.
        context.touchIDAuthenticationAllowableReuseDuration = 0
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch let error as LAError where [.userCancel, .systemCancel, .appCancel].contains(error.code) {
            throw DeviceKeyError.cancelled
        } catch let error as LAError where error.code == .passcodeNotSet {
            throw DeviceKeyError.noPasscode
        }
        return context
    }

    /// macOS puts "Hotify is trying to" in front of the reason. iOS shows it on its own.
    static func reason(_ phrase: String) -> String {
        #if os(macOS)
        phrase
        #else
        phrase.prefix(1).uppercased() + phrase.dropFirst() + "."
        #endif
    }

    /// Whether the key is still there, without asking the owner. A protected item that exists answers that it needs
    /// interaction, which is enough.
    private static func exists() -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        var query = baseQuery
        query[kSecUseAuthenticationContext as String] = context
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    private static func store(_ key: Curve25519.Signing.PrivateKey) throws {
        SecItemDelete(baseQuery as CFDictionary)
        var error: Unmanaged<CFError>?
        // Only while a passcode is set, and only on this device. `userPresence` asks for biometrics or the passcode.
        guard
            let access = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, &error)
        else { throw DeviceKeyError.noPasscode }
        var item = baseQuery
        item[kSecValueData as String] = key.rawRepresentation
        item[kSecAttrAccessControl as String] = access
        let status = SecItemAdd(item as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecAuthFailed, errSecNotAvailable, errSecDecode:
            throw DeviceKeyError.noPasscode
        default:
            throw DeviceKeyError.keychain(status)
        }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    /// `hotify-` and the device's name, so a server's `authorized_keys` says where the line came from.
    private static var comment: String {
        #if os(macOS)
        let name = Host.current().localizedName ?? "mac"
        #else
        let name = UIDevice.current.name
        #endif
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let cleaned = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        return "hotify-" + (cleaned.isEmpty ? "device" : cleaned)
    }
}

enum DeviceKeyError: Error, Equatable {
    /// The owner closed the prompt.
    case cancelled
    /// The device has no passcode, so the key can't be kept.
    case noPasscode
    /// The key is gone, as happens when the passcode was removed.
    case missing
    case keychain(OSStatus)
}

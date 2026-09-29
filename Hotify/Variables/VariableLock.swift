import LocalAuthentication
import SwiftUI

/// Keeps environment variable values hidden until the device owner confirms with Face ID, Touch ID, or the passcode.
///
/// One unlock covers every resource. Values lock again after `unlockDuration`, and when Hotify goes to the background.
@Observable
final class VariableLock {
    static let unlockDuration: Duration = .seconds(5 * 60)
    private static let requirementKey = "requiresUnlockForVariables"

    /// The setting. On unless the user turned it off.
    private(set) var isRequired: Bool
    /// When the current unlock runs out. `nil` while locked.
    private(set) var unlockedUntil: Date?
    /// Why the last attempt failed, in words for the user. A cancelled prompt leaves this empty.
    private(set) var failure: String?
    private(set) var isAuthenticating = false
    let method: UnlockMethod

    private let defaults: UserDefaults
    private var relock: Task<Void, Never>?

    /// Pass `isRequired` to override the saved setting without writing it, as a preview does.
    init(defaults: UserDefaults = .standard, isRequired: Bool? = nil) {
        self.defaults = defaults
        self.isRequired = isRequired ?? (defaults.object(forKey: Self.requirementKey) as? Bool ?? true)
        method = UnlockMethod.current()
    }

    /// Whether values may show right now.
    var isOpen: Bool { !isRequired || unlockedUntil != nil }

    /// Asks for Face ID, Touch ID, or the passcode, unless values already show. Returns whether they do now.
    @discardableResult
    func unlock() async -> Bool {
        guard !isOpen else { return true }
        guard await authenticate(reason: Self.reason("show environment variable values")) else { return false }
        unlockedUntil = .now.addingTimeInterval(TimeInterval(Self.unlockDuration.components.seconds))
        relock?.cancel()
        relock = Task { [weak self] in
            try? await Task.sleep(for: Self.unlockDuration)
            guard !Task.isCancelled else { return }
            self?.lock()
        }
        return true
    }

    func lock() {
        relock?.cancel()
        relock = nil
        unlockedUntil = nil
    }

    /// Turning the lock off asks first, so whoever holds an unlocked device cannot switch it off unnoticed.
    func setRequired(_ required: Bool) async {
        guard required != isRequired else { return }
        // A device without a passcode has no owner to ask. Refusing here would leave the values locked for good.
        if !required, method != .unavailable {
            guard await authenticate(reason: Self.reason("turn off the lock for environment variables")) else { return }
        }
        isRequired = required
        defaults.set(required, forKey: Self.requirementKey)
        failure = nil
        lock()
    }

    private func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            failure =
                "This \(UnlockMethod.deviceName) has no \(UnlockMethod.secretName) set. Set one to unlock values, or turn the lock off in Settings."
            return false
        }
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            failure = nil
            return true
        } catch let error as LAError where [.userCancel, .systemCancel, .appCancel].contains(error.code) {
            failure = nil
            return false
        } catch {
            failure = error.localizedDescription
            return false
        }
    }

    /// macOS puts "Hotify is trying to" in front of the reason. iOS shows it on its own.
    private static func reason(_ phrase: String) -> String {
        #if os(macOS)
        phrase
        #else
        phrase.prefix(1).uppercased() + phrase.dropFirst() + "."
        #endif
    }
}

/// How this device confirms its owner, for labels such as "Unlock with Face ID".
enum UnlockMethod: Hashable {
    case faceID
    case touchID
    case opticID
    case passcode
    /// No passcode is set, so nothing can confirm the owner.
    case unavailable

    static func current() -> UnlockMethod {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return .unavailable }
        // `biometryType` is only filled in after a `canEvaluatePolicy` call.
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .passcode
        }
    }

    /// "Face ID", or "Passcode" when the device has no biometrics.
    var title: String {
        switch self {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        case .passcode, .unavailable: Self.secretName.prefix(1).uppercased() + Self.secretName.dropFirst()
        }
    }

    /// "Face ID or passcode", naming the fallback the system offers.
    var titleWithFallback: String {
        switch self {
        case .faceID, .touchID, .opticID: "\(title) or \(Self.secretName)"
        case .passcode, .unavailable: title
        }
    }

    var systemImage: String {
        switch self {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        case .passcode, .unavailable: "lock"
        }
    }

    static var secretName: String {
        #if os(macOS)
        "password"
        #else
        "passcode"
        #endif
    }

    static var deviceName: String {
        #if os(macOS)
        "Mac"
        #else
        "device"
        #endif
    }
}

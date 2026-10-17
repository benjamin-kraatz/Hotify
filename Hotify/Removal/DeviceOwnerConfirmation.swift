import LocalAuthentication

/// Confirms the device owner with Face ID, Touch ID, or the passcode, with a new context for every prompt.
///
/// It shares nothing with `VariableLock`, so values shown a minute ago never stand in for a delete.
@MainActor
final class DeviceOwnerConfirmation: OwnerConfirming {
    private var context: LAContext?

    func confirmOwner(reason: String) async -> OwnerConfirmation {
        context?.invalidate()
        let context = LAContext()
        // A fingerprint that just unlocked the Mac or the variables does not count for this prompt.
        context.touchIDAuthenticationAllowableReuseDuration = 0
        self.context = context
        defer {
            if self.context === context { self.context = nil }
        }
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return Self.answer(for: error)
        }
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: Self.reason(reason))
            return .confirmed
        } catch {
            return Self.answer(for: error as NSError)
        }
    }

    func cancel() {
        context?.invalidate()
        context = nil
    }

    private static func answer(for error: NSError?) -> OwnerConfirmation {
        guard let error, error.domain == LAError.errorDomain else {
            return .failed(error?.localizedDescription ?? "Hotify could not confirm it's you.")
        }
        switch LAError.Code(rawValue: error.code) {
        case .userCancel, .systemCancel, .appCancel, .userFallback:
            return .cancelled
        case .passcodeNotSet:
            return .unavailable
        default:
            return .failed(error.localizedDescription)
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

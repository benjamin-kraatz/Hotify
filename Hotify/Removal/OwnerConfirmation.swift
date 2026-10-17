import Foundation

/// How a request to confirm the device owner ended.
enum OwnerConfirmation: Equatable, Sendable {
    case confirmed
    /// The owner, the system, or Hotify called the prompt off.
    case cancelled
    /// No passcode or password is set, so nothing can confirm the owner.
    case unavailable
    /// The prompt failed, in words for the user.
    case failed(String)
}

/// Asks the device owner to confirm one action. Every call asks anew.
@MainActor
protocol OwnerConfirming: AnyObject {
    /// Asks for Face ID, Touch ID, or the passcode. Pass `reason` as the phrase after "Hotify is trying to".
    func confirmOwner(reason: String) async -> OwnerConfirmation
    /// Ends a prompt that is still up, which then answers `.cancelled`.
    func cancel()
}

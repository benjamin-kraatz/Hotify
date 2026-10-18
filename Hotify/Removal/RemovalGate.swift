import Foundation
import Observation

/// Sends a delete only after the device owner confirms it, fresh, for that one target.
///
/// The target is fixed when the delete is asked for and is the one the request goes to. A second delete waits for
/// the first to end. Cancelling while the prompt is up, or moving to another target, means nothing is sent, even if
/// the owner confirms after all.
@MainActor
@Observable
final class RemovalGate<Target: Hashable & Sendable> {
    enum Phase: Equatable {
        case idle
        case confirming(Target)
        case removing(Target)
    }

    /// Why the last delete did not go through.
    enum Problem: Equatable {
        case cancelled
        case unavailable
        case notConfirmed(String)
        case refused(String)
    }

    enum Outcome: Equatable {
        case removed
        /// Another delete was underway, so this one was not asked for.
        case busy
        /// Cancelled or replaced while the owner was asked. Nothing was sent.
        case withdrawn
        case notConfirmed(OwnerConfirmation)
        /// The request went out and failed.
        case failed
    }

    private(set) var phase: Phase = .idle
    private(set) var problem: Problem?

    private let confirmer: any OwnerConfirming
    private let describe: (any Error) -> String
    private var ticket = 0

    /// `describe` words a failed request for the user.
    init(confirmer: any OwnerConfirming, describe: @escaping (any Error) -> String = { $0.localizedDescription }) {
        self.confirmer = confirmer
        self.describe = describe
    }

    var isBusy: Bool { phase != .idle }

    var isRemoving: Bool {
        if case .removing = phase { true } else { false }
    }

    /// Asks the owner, then hands `target`, and only it, to `send`.
    func remove(_ target: Target, reason: String, send: (Target) async throws -> Void) async -> Outcome {
        guard phase == .idle else { return .busy }
        ticket &+= 1
        let current = ticket
        problem = nil
        phase = .confirming(target)
        let answer = await confirmer.confirmOwner(reason: reason)
        guard ticket == current, phase == .confirming(target) else { return .withdrawn }
        guard answer == .confirmed else {
            phase = .idle
            problem = Problem(answer)
            return .notConfirmed(answer)
        }
        phase = .removing(target)
        do {
            try await send(target)
            phase = .idle
            return .removed
        } catch {
            phase = .idle
            problem = .refused(describe(error))
            return .failed
        }
    }

    /// Withdraws a delete the owner has not confirmed yet, and forgets the last problem. A request already sent
    /// goes on.
    func cancel() {
        if case .confirming = phase {
            ticket &+= 1
            phase = .idle
            confirmer.cancel()
        }
        if phase == .idle {
            problem = nil
        }
    }
}

extension RemovalGate.Problem {
    fileprivate init?(_ answer: OwnerConfirmation) {
        switch answer {
        case .confirmed: return nil
        case .cancelled: self = .cancelled
        case .unavailable: self = .unavailable
        case .failed(let message): self = .notConfirmed(message)
        }
    }
}

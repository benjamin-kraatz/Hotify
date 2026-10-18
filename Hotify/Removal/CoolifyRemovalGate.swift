import CoolifyAPI
import Foundation

/// The gate every delete of an application, database, service, project, or environment goes through.
typealias CoolifyRemovalGate = RemovalGate<RemovalTarget>

extension RemovalGate where Target == RemovalTarget {
    /// Asks with Face ID, Touch ID, or the passcode, and words a refused request the way Coolify gives it.
    convenience init() {
        self.init(confirmer: DeviceOwnerConfirmation()) { error in
            (error as? CoolifyError)?.summary ?? error.localizedDescription
        }
    }

    /// Asks the owner to confirm deleting `name`, then sends `target` over `client`.
    @discardableResult
    func remove(_ target: RemovalTarget, named name: String, with client: CoolifyClient) async -> Outcome {
        await remove(target, named: name) { target in
            _ = try await client.remove(target)
        }
    }

    /// Asks the owner to confirm deleting `name`, then hands `target` to `send`.
    @discardableResult
    func remove(
        _ target: RemovalTarget, named name: String, send: (RemovalTarget) async throws -> Void
    ) async -> Outcome {
        await remove(target, reason: "delete \(name)", send: send)
    }

    /// Where a delete stands, for the confirmation on screen.
    var status: RemovalStatus {
        switch phase {
        case .confirming: .confirming
        case .removing: .deleting
        case .idle: problem.map(RemovalStatus.init) ?? .ready
        }
    }
}

/// Where a delete stands: ready, waiting on the owner, sent, or stopped and why.
enum RemovalStatus: Equatable {
    case ready
    case confirming
    case deleting
    /// The owner cancelled the prompt. Nothing was sent.
    case cancelled
    /// Nothing was sent, or Coolify refused, in words for the user.
    case problem(String)

    /// "Waiting for Touch ID or password to delete Website…", while a delete is underway, for a page with no dialog
    /// of its own. `nil` when nothing is underway.
    func progress(deleting name: String, with method: UnlockMethod) -> String? {
        switch self {
        case .confirming: "Waiting for \(method.promptName) to delete \(name)…"
        case .deleting: "Coolify is deleting \(name)…"
        case .ready, .cancelled, .problem: nil
        }
    }

    fileprivate init(_ problem: RemovalGate<RemovalTarget>.Problem) {
        switch problem {
        case .cancelled:
            self = .cancelled
        case .unavailable:
            self = .problem(
                "Set a \(UnlockMethod.secretName) on this \(UnlockMethod.deviceName) to delete from Hotify. "
                    + "Hotify asks for it before every delete. Nothing was deleted.")
        case .notConfirmed(let message):
            self = .problem("\(message) Nothing was deleted.")
        case .refused(let message):
            self = .problem(message)
        }
    }

    var isBusy: Bool { self == .confirming || self == .deleting }

    /// A problem to show in a banner. A cancelled prompt needs none.
    var notice: String? {
        if case .problem(let message) = self { message } else { nil }
    }
}

extension UnlockMethod {
    /// "Touch ID or password", or "your password", for a sentence about what a delete asks for.
    var promptName: String {
        switch self {
        case .faceID, .touchID, .opticID: titleWithFallback
        case .passcode, .unavailable: "your \(Self.secretName)"
        }
    }
}

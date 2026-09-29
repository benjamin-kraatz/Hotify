import Foundation

/// Confirmed writes and the first unconfirmed key. A failed response never triggers an automatic retry.
public struct VariableSyncResult: Sendable {
    public var appliedKeys: [String]
    public var failedKey: String?
}

extension CoolifyClient {
    /// Rechecks the destination scope, then applies reviewed writes in order. Stops on the first failed response.
    public func applyVariableSync(
        _ changes: [VariableSyncChange], plan: VariableSyncPlan, to owner: EnvironmentVariableOwner
    ) async throws -> VariableSyncResult {
        let current = try await environmentVariables(of: owner).filter { $0.isPreview == plan.destinationPreview }
        guard Set(current) == Set(plan.destination) else {
            throw CoolifyError(
                message: "Destination variables changed after comparison. Compare again before applying.")
        }
        var result = VariableSyncResult(appliedKeys: [])
        // Remove destination-only keys only after the selected creates and updates succeed.
        let ordered = changes.filter { $0.kind != .destinationOnly } + changes.filter { $0.kind == .destinationOnly }
        for change in ordered {
            do {
                try Task.checkCancellation()
                switch change.kind {
                case .create:
                    guard let draft = change.draft else { continue }
                    _ = try await createEnvironmentVariable(draft, on: owner)
                case .update:
                    guard let draft = change.draft else { continue }
                    _ = try await updateEnvironmentVariable(draft, on: owner)
                case .destinationOnly:
                    guard let uuid = change.destination?.uuid, !uuid.isEmpty else {
                        throw CoolifyError(message: "The destination variable has no identifier.")
                    }
                    try await deleteEnvironmentVariable(uuid, from: owner)
                case .unchanged, .unavailable: continue
                }
                result.appliedKeys.append(change.key)
            } catch {
                result.failedKey = change.key
                return result
            }
        }
        return result
    }
}

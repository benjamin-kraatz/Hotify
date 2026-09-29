import Foundation

/// A reviewable, one-direction comparison of two variable scopes. Values never leave memory.
public struct VariableSyncPlan: Sendable {
    public let source: [EnvironmentVariable]
    public let destination: [EnvironmentVariable]
    public let changes: [VariableSyncChange]
    public let destinationPreview: Bool

    public init(
        source: [EnvironmentVariable], destination: [EnvironmentVariable], sourcePreview: Bool,
        destinationPreview: Bool, destinationIsApplication: Bool
    ) throws {
        self.source = source.filter { $0.isPreview == sourcePreview }
        self.destination = destination.filter { $0.isPreview == destinationPreview }
        self.destinationPreview = destinationPreview
        guard Set(self.source.map(\.key)).count == self.source.count,
            Set(self.destination.map(\.key)).count == self.destination.count
        else {
            throw CoolifyError(message: "Coolify returned duplicate variable keys. Resolve them before syncing.")
        }
        let existing = Dictionary(uniqueKeysWithValues: self.destination.map { ($0.key, $0) })
        let incoming = Set(self.source.map(\.key))
        var changes: [VariableSyncChange] = self.source.map { variable in
            let target = existing[variable.key]
            guard let value = variable.value else {
                return VariableSyncChange(
                    key: variable.key, kind: .unavailable, source: variable, destination: target, draft: nil)
            }
            let draft = EnvironmentVariableDraft(
                key: variable.key, value: value,
                isPreview: destinationIsApplication ? destinationPreview : nil,
                isLiteral: variable.isLiteral, isMultiline: variable.isMultiline, isShownOnce: variable.isShownOnce,
                isRuntime: destinationIsApplication ? (variable.isRuntime ?? target?.isRuntime ?? true) : nil,
                isBuildtime: destinationIsApplication ? (variable.isBuildtime ?? target?.isBuildtime ?? true) : nil,
                comment: variable.comment ?? "")
            let same =
                target.map { target in
                    target.value == value && target.isLiteral == draft.isLiteral
                        && target.isMultiline == draft.isMultiline
                        && target.isShownOnce == draft.isShownOnce && (target.comment ?? "") == draft.comment
                        && (!destinationIsApplication
                            || ((target.isRuntime ?? true) == draft.isRuntime
                                && (target.isBuildtime ?? true) == draft.isBuildtime))
                } ?? false
            return VariableSyncChange(
                key: variable.key, kind: same ? .unchanged : (target == nil ? .create : .update), source: variable,
                destination: target, draft: draft)
        }
        changes += self.destination.filter { !incoming.contains($0.key) }.map {
            VariableSyncChange(key: $0.key, kind: .destinationOnly, source: nil, destination: $0, draft: nil)
        }
        self.changes = changes.sorted { $0.key < $1.key }
    }
}

/// A single proposed variable write, or a reason that no write can be made.
public struct VariableSyncChange: Sendable, Identifiable {
    /// Whether a key needs a write, a deletion decision, or no action.
    public enum Kind: String, Sendable {
        case create, update, unchanged, unavailable, destinationOnly
    }
    public let key: String
    public let kind: Kind
    public let source: EnvironmentVariable?
    public let destination: EnvironmentVariable?
    public let draft: EnvironmentVariableDraft?
    public var id: String { key }
}

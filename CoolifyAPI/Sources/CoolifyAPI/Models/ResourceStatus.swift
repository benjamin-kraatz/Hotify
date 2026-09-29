import Foundation

/// Coolify stores container status as `state:health` and sometimes `state:health:excluded`.
public struct ResourceStatus: Sendable, Hashable {
    public var raw: String
    public var state: String
    public var health: String?
    public var isExcluded: Bool

    public init(raw: String) {
        self.raw = raw
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        state = parts.first ?? ""
        if parts.count > 1, !parts[1].isEmpty {
            health = parts[1]
        } else {
            health = nil
        }
        isExcluded = parts.dropFirst(2).contains("excluded")
    }

    public var isRunning: Bool {
        switch state {
        case "running", "degraded", "restarting", "starting":
            true
        default:
            false
        }
    }
}

public protocol HasResourceStatus {
    var status: String? { get }
}

public extension HasResourceStatus {
    var parsedStatus: ResourceStatus? {
        status.map(ResourceStatus.init(raw:))
    }
}

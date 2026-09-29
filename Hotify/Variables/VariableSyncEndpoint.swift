import CoolifyAPI
import Foundation

/// A saved instance and resource selected for a manual variable comparison.
struct VariableSyncEndpoint: Hashable {
    var instanceID: UUID
    var instanceName: String
    var resource: ResourceSummary

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.instanceID == rhs.instanceID && lhs.resource.route == rhs.resource.route
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(instanceID)
        hasher.combine(resource.route)
    }
    var label: String { "\(instanceName) / \(resource.name)" }
}

import Foundation

/// Where a new service goes: a server and its network, and a project's environment.
struct Placement: Codable, Hashable {
    var serverUUID: String?
    var projectUUID: String?
    var environmentUUID: String?
    /// Only set when the server has more than one network to choose from.
    var destinationUUID: String?

    var isComplete: Bool {
        serverUUID != nil && projectUUID != nil && environmentUUID != nil
    }

    /// The last placement used on an instance, so the next service lands beside the previous one.
    /// It holds uuids only, nothing secret, so UserDefaults is fine.
    static func remembered(for instanceID: UUID) -> Placement? {
        guard let data = UserDefaults.standard.data(forKey: key(instanceID)) else { return nil }
        return try? JSONDecoder().decode(Placement.self, from: data)
    }

    func remember(for instanceID: UUID) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key(instanceID))
    }

    private static func key(_ instanceID: UUID) -> String {
        "provisioning.placement.\(instanceID.uuidString)"
    }
}

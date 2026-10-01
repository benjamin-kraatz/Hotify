import CoolifyAPI
import Foundation

/// Finds an instance the app saved and builds a client for it from the shared Keychain item.
enum InstanceAccess {
    static func instance(_ id: UUID) -> CoolifyInstance? {
        AppGroup.instances().first { $0.id == id }
    }

    /// The instance and a client, or the reason there is none.
    static func client(for id: UUID) -> Result<(CoolifyInstance, CoolifyClient), AccessError> {
        guard let instance = instance(id) else { return .failure(.problem(.noInstance)) }
        guard let token = TokenStore.load(for: id),
            let client = try? CoolifyClient(instanceURL: instance.baseURL, token: token)
        else { return .failure(.problem(.noToken)) }
        return .success((instance, client))
    }

    struct AccessError: Error {
        var problem: ReadingProblem
        static func problem(_ problem: ReadingProblem) -> AccessError { AccessError(problem: problem) }
    }
}

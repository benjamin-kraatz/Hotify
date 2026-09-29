import Foundation

/// The resource whose environment variables a request reads or changes.
public enum EnvironmentVariableOwner: Sendable, Hashable {
    case application(String)
    case database(String)
    case service(String)

    var path: String {
        switch self {
        case .application(let uuid): "applications/\(CoolifyURL.encodePathComponent(uuid))/envs"
        case .database(let uuid): "databases/\(CoolifyURL.encodePathComponent(uuid))/envs"
        case .service(let uuid): "services/\(CoolifyURL.encodePathComponent(uuid))/envs"
        }
    }
}

extension CoolifyClient {
    /// Lists the owner's variables. For an application, production variables come first, then preview ones.
    public func environmentVariables(of owner: EnvironmentVariableOwner) async throws -> [EnvironmentVariable] {
        try await getList(owner.path)
    }

    /// Adds a variable. Coolify answers 409 when the key already exists.
    public func createEnvironmentVariable(
        _ draft: EnvironmentVariableDraft,
        on owner: EnvironmentVariableOwner
    ) async throws -> EnvironmentVariable {
        try await post(owner.path, body: draft)
    }

    /// Replaces the value and flags of the variable with `draft.key`.
    ///
    /// Coolify finds the variable by key, not uuid, so a key cannot be renamed here. For an application it
    /// looks among preview variables when `draft.isPreview` is true, and among production ones otherwise.
    public func updateEnvironmentVariable(
        _ draft: EnvironmentVariableDraft,
        on owner: EnvironmentVariableOwner
    ) async throws -> EnvironmentVariable {
        try await patch(owner.path, body: draft)
    }

    public func deleteEnvironmentVariable(_ uuid: String, from owner: EnvironmentVariableOwner) async throws {
        let _: QueuedAction = try await delete("\(owner.path)/\(CoolifyURL.encodePathComponent(uuid))")
    }
}

import Foundation

/// The project or environment whose shared variables a request reads or changes.
public enum SharedVariableScope: Sendable, Hashable {
    case project(String)
    /// One environment of a project. Coolify takes the environment's uuid or its name.
    case environment(project: String, environment: String)

    var path: String {
        switch self {
        case .project(let uuid):
            "projects/\(CoolifyURL.encodePathComponent(uuid))/envs"
        case .environment(let project, let environment):
            "projects/\(CoolifyURL.encodePathComponent(project))/environments/\(CoolifyURL.encodePathComponent(environment))/envs"
        }
    }
}

extension CoolifyClient {
    /// Lists the scope's shared variables, oldest first. The OpenAPI spec gives this response no schema.
    public func sharedVariables(in scope: SharedVariableScope) async throws -> [SharedVariable] {
        try await getList(scope.path)
    }

    /// Adds a shared variable and returns its id, which is all Coolify sends back.
    /// Coolify answers 409 when the scope already has the key.
    public func createSharedVariable(_ draft: SharedVariableDraft, in scope: SharedVariableScope) async throws -> Int {
        let created: CreatedSharedVariable = try await post(scope.path, body: draft)
        return created.id
    }

    /// Replaces the key, value, and flags of the variable with this id.
    public func updateSharedVariable(
        _ id: Int,
        with draft: SharedVariableDraft,
        in scope: SharedVariableScope
    ) async throws -> SharedVariable {
        try await patch("\(scope.path)/\(id)", body: draft)
    }

    public func deleteSharedVariable(_ id: Int, from scope: SharedVariableScope) async throws {
        let _: QueuedAction = try await delete("\(scope.path)/\(id)")
    }
}

private struct CreatedSharedVariable: Decodable {
    var id: Int

    enum CodingKeys: String, CodingKey {
        case id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = container.flexInt(.id) else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "Created shared variable is missing an id."
            )
        }
        self.id = id
    }
}

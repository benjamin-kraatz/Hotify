import Foundation

extension CoolifyClient {
    public func projects() async throws -> [Project] {
        try await getList("projects")
    }

    public func project(_ uuid: String) async throws -> Project {
        try await get("projects/\(CoolifyURL.encodePathComponent(uuid))")
    }

    /// Changes a project's name and description. An empty description clears it.
    ///
    /// The response carries only the uuid, name, and description, so the returned project has no environments.
    public func updateProject(_ uuid: String, name: String, description: String) async throws -> Project {
        try await patch(
            "projects/\(CoolifyURL.encodePathComponent(uuid))",
            body: PlaceChanges(name: name, description: description)
        )
    }

    /// Changes an environment's name and description. `environment` is its uuid or its current name.
    /// An empty description clears it.
    public func updateEnvironment(
        _ environment: String,
        inProject uuid: String,
        name: String,
        description: String
    ) async throws -> Environment {
        try await patch(
            "projects/\(CoolifyURL.encodePathComponent(uuid))/environments/\(CoolifyURL.encodePathComponent(environment))",
            body: PlaceChanges(name: name, description: description)
        )
    }
}

/// The body for renaming a project or an environment. Coolify answers 422 to any other field.
private struct PlaceChanges: Encodable {
    var name: String
    var description: String
}

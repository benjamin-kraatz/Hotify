import Foundation

extension CoolifyClient {
    /// Creates a one-click service from a template. It stays stopped unless `draft.instantDeploy` is set.
    ///
    /// Coolify answers 409 with `CoolifyError.conflicts` when a requested domain is taken, and 404 when this instance
    /// does not know the template yet.
    public func createService(_ draft: ServiceDraft) async throws -> CreatedService {
        try await post("services", body: draft)
    }

    /// Creates a database, and starts it when the draft says so. Coolify generates its password and answers with
    /// the connection strings, which hold it.
    ///
    /// Coolify answers 400 when a public port is taken.
    public func createDatabase(_ draft: DatabaseDraft) async throws -> CreatedDatabase {
        try await post("databases/\(draft.engine.rawValue)", body: draft)
    }

    /// Changes a service. Coolify parses its compose file again afterwards, so new variables appear.
    public func updateService(_ uuid: String, _ update: ServiceUpdate) async throws -> CreatedService {
        try await patch("services/\(CoolifyURL.encodePathComponent(uuid))", body: update)
    }

    /// Deletes a service with its containers, volumes, configuration, and networks.
    public func deleteService(_ uuid: String) async throws {
        let _: QueuedAction = try await delete(
            "services/\(CoolifyURL.encodePathComponent(uuid))",
            query: [
                URLQueryItem(name: "delete_configurations", value: "true"),
                URLQueryItem(name: "delete_volumes", value: "true"),
                URLQueryItem(name: "docker_cleanup", value: "true"),
                URLQueryItem(name: "delete_connected_networks", value: "true"),
            ]
        )
    }

    public func destinations(onServer uuid: String) async throws -> [Destination] {
        try await getList("servers/\(CoolifyURL.encodePathComponent(uuid))/destinations")
    }

    public func createProject(name: String, description: String? = nil) async throws -> CreatedResource {
        try await post("projects", body: NewProject(name: name, description: description))
    }

    /// Adds an environment to a project. Coolify answers 409 when the project already has one by that name.
    public func createEnvironment(name: String, inProject uuid: String) async throws -> CreatedResource {
        try await post(
            "projects/\(CoolifyURL.encodePathComponent(uuid))/environments", body: NewEnvironment(name: name))
    }
}

private struct NewProject: Encodable {
    var name: String
    var description: String?
}

private struct NewEnvironment: Encodable {
    var name: String
}

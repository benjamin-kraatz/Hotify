import Foundation

extension CoolifyClient {
    /// Checks that Coolify can use the server.
    ///
    /// `install` defaults to false, which only validates. Pass true to install missing prerequisites.
    /// That can restart Docker.
    public func validateServer(uuid: String, install: Bool = false) async throws -> QueuedAction {
        // Always name `install`, including false, so a check never installs prerequisites.
        try await post(serverPath(uuid, "validate"), body: ValidateServerBody(install: install))
    }

    /// The server's Docker cleanup schedule and the flags a run uses.
    public func dockerCleanup(uuid: String) async throws -> DockerCleanupSettings {
        try await get(serverPath(uuid, "docker-cleanup"))
    }

    /// Changes the server's Docker cleanup settings. Nil fields stay out of the body, so Coolify keeps them.
    ///
    /// Coolify 4.3 answers 422 when the body contains a key it does not expect.
    public func updateDockerCleanup(
        uuid: String,
        settings: DockerCleanupSettings
    ) async throws -> DockerCleanupSettings {
        try await patch(serverPath(uuid, "docker-cleanup"), body: settings)
    }

    /// Queues a Docker cleanup now. A nil flag is left out of the body.
    ///
    /// Pass a delete flag only for a run that should delete unused volumes or networks.
    public func runDockerCleanup(
        uuid: String,
        deleteUnusedVolumes: Bool? = nil,
        deleteUnusedNetworks: Bool? = nil
    ) async throws -> QueuedAction {
        try await post(
            serverPath(uuid, "docker-cleanup/run"),
            body: DockerCleanupRun(deleteUnusedVolumes: deleteUnusedVolumes, deleteUnusedNetworks: deleteUnusedNetworks)
        )
    }

    public func dockerCleanupExecutions(uuid: String) async throws -> [DockerCleanupExecution] {
        try await getList(serverPath(uuid, "docker-cleanup/executions"))
    }

    /// The proxy's type and status. Does not read the raw compose configuration.
    public func serverProxy(uuid: String) async throws -> ServerProxy {
        try await get(serverPath(uuid, "proxy"))
    }

    /// Queues a restart of the server's proxy. Domains on the server drop until the proxy is back.
    public func restartServerProxy(uuid: String) async throws -> QueuedAction {
        try await post(serverPath(uuid, "proxy/restart"))
    }

    /// Domains on the server, grouped by the address they use.
    public func serverDomains(uuid: String) async throws -> [ServerDomainGroup] {
        try await getList(serverPath(uuid, "domains"))
    }

    private func serverPath(_ uuid: String, _ suffix: String) -> String {
        "servers/\(CoolifyURL.encodePathComponent(uuid))/\(suffix)"
    }
}

private struct ValidateServerBody: Encodable {
    var install: Bool
}

/// Flags for one cleanup run. Nil stays out of the JSON.
private struct DockerCleanupRun: Encodable {
    var deleteUnusedVolumes: Bool?
    var deleteUnusedNetworks: Bool?

    enum CodingKeys: String, CodingKey {
        case deleteUnusedVolumes
        case deleteUnusedNetworks
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(deleteUnusedVolumes, forKey: .deleteUnusedVolumes)
        try container.encodeIfPresent(deleteUnusedNetworks, forKey: .deleteUnusedNetworks)
    }
}

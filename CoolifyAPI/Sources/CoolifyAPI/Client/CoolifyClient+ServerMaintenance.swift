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
    ///
    /// Use `serverProxyReading` when the editor needs the compose file. That file stays off `ServerProxy`.
    public func serverProxy(uuid: String) async throws -> ServerProxy {
        try await get(serverPath(uuid, "proxy"))
    }

    /// Proxy settings, and the compose file when the response included it.
    ///
    /// Coolify omits `configuration` unless the token has `read:sensitive`. The file can hold secrets, so a missing
    /// or null field comes back as nil and is never logged.
    public func serverProxyReading(uuid: String) async throws -> ServerProxyReading {
        let payload: ServerProxyPayload = try await get(serverPath(uuid, "proxy"))
        return payload.reading
    }

    /// Changes the proxy's redirect, exact labels, and type. Nil arguments stay out of the body.
    ///
    /// Pass `clearRedirectURL` to send `redirect_url` as null, which clears a stored URL. Omit the URL when it did
    /// not change. This request does not send the compose file.
    public func updateServerProxy(
        uuid: String,
        redirectEnabled: Bool? = nil,
        redirectURL: String? = nil,
        clearRedirectURL: Bool = false,
        generateExactLabels: Bool? = nil,
        proxyType: String? = nil
    ) async throws -> ServerProxy {
        let url = redirectURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = proxyType?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = ServerProxyUpdate(
            redirectEnabled: redirectEnabled,
            redirectUrl: (url?.isEmpty == false) ? url : nil,
            clearRedirectUrl: clearRedirectURL,
            generateExactLabels: generateExactLabels,
            proxyType: (type?.isEmpty == false) ? type : nil
        )
        return try await patch(serverPath(uuid, "proxy"), body: body)
    }

    /// Replaces the proxy compose file. Coolify expects multi-line YAML as base64, so the raw text is encoded.
    ///
    /// The file can hold secrets. It is not logged.
    public func saveServerProxyConfiguration(uuid: String, configuration: String) async throws -> ServerProxy {
        // The spec says multi-line proxy compose must be base64, same as other compose payloads.
        let encoded = Data(configuration.utf8).base64EncodedString()
        return try await put(
            serverPath(uuid, "proxy/configuration"),
            body: ServerProxyConfigurationBody(configuration: encoded)
        )
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

/// Patch body for a server proxy. Nil stays out of the JSON, and the compose file is not a field here.
private struct ServerProxyUpdate: Encodable {
    var redirectEnabled: Bool?
    var redirectUrl: String?
    var clearRedirectUrl: Bool
    var generateExactLabels: Bool?
    var proxyType: String?

    enum CodingKeys: String, CodingKey {
        case redirectEnabled
        case redirectUrl
        case generateExactLabels
        case proxyType
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(redirectEnabled, forKey: .redirectEnabled)
        if clearRedirectUrl {
            try container.encodeNil(forKey: .redirectUrl)
        } else {
            try container.encodeIfPresent(redirectUrl, forKey: .redirectUrl)
        }
        try container.encodeIfPresent(generateExactLabels, forKey: .generateExactLabels)
        try container.encodeIfPresent(proxyType, forKey: .proxyType)
    }
}

private struct ServerProxyConfigurationBody: Encodable {
    var configuration: String
}

/// GET /servers/{uuid}/proxy, including the compose file only when the JSON actually has it.
private struct ServerProxyPayload: Decodable {
    var reading: ServerProxyReading

    enum CodingKeys: String, CodingKey {
        case status
        case proxyType
        case redirectEnabled
        case redirectUrl
        case configuration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let proxy = ServerProxy(
            status: container.flexString(.status),
            proxyType: container.flexString(.proxyType),
            redirectEnabled: container.flexBool(.redirectEnabled),
            redirectUrl: container.flexString(.redirectUrl)
        )
        reading = ServerProxyReading(proxy: proxy, configuration: Self.returnedConfiguration(container))
    }

    /// A missing or null `configuration` means the file was not returned. Do not substitute one.
    private static func returnedConfiguration(_ container: KeyedDecodingContainer<CodingKeys>) -> String? {
        guard container.contains(.configuration) else { return nil }
        if (try? container.decodeNil(forKey: .configuration)) == true { return nil }
        return container.flexString(.configuration)
    }
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

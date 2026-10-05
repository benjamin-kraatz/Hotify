import Foundation

extension CoolifyClient {
    /// The server's stored Cloudflare Tunnel flag and addresses.
    public func cloudflareTunnel(uuid: String) async throws -> CloudflareTunnel {
        try await get(serverTunnelPath(uuid, "cloudflare-tunnel"))
    }

    /// Sets `is_cloudflare_tunnel` and leaves every other key out of the body.
    ///
    /// Coolify 4.3 answers 422 when the body contains a key it does not expect. This does not deploy cloudflared.
    public func updateCloudflareTunnel(uuid: String, isCloudflareTunnel: Bool) async throws -> CloudflareTunnel {
        try await patch(
            serverTunnelPath(uuid, "cloudflare-tunnel"),
            body: CloudflareTunnelUpdate(isCloudflareTunnel: isCloudflareTunnel)
        )
    }

    /// Marks the tunnel enabled. Coolify does not deploy cloudflared.
    public func enableCloudflareTunnel(uuid: String) async throws -> CloudflareTunnel {
        try await post(serverTunnelPath(uuid, "cloudflare-tunnel/enable"))
    }

    /// Marks the tunnel disabled and restores `ip_previous` when Coolify has it.
    ///
    /// Coolify does not remove a remote cloudflared container.
    public func disableCloudflareTunnel(uuid: String) async throws -> CloudflareTunnel {
        try await post(serverTunnelPath(uuid, "cloudflare-tunnel/disable"))
    }

    private func serverTunnelPath(_ uuid: String, _ suffix: String) -> String {
        "servers/\(CoolifyURL.encodePathComponent(uuid))/\(suffix)"
    }
}

/// The only key PATCH accepts. Anything else is a 422.
private struct CloudflareTunnelUpdate: Encodable {
    var isCloudflareTunnel: Bool
}

import CoolifyAPI
import Foundation

/// The Cloudflare Tunnel flag for one server. The section loads it; the rest of the server page does not.
@Observable
final class CloudflareTunnelModel {
    var tunnel: CloudflareTunnel?
    var error: String?
    var isUpdating = false
    private(set) var hasLoaded = false

    func load(client: CoolifyClient?, server uuid: String) async {
        guard let client, !isUpdating else { return }
        do {
            tunnel = try await client.cloudflareTunnel(uuid: uuid)
            hasLoaded = true
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = Self.message(for: error)
        }
    }

    func enable(client: CoolifyClient, server uuid: String) async {
        await change(to: true, client: client, server: uuid)
    }

    func disable(client: CoolifyClient, server uuid: String) async {
        await change(to: false, client: client, server: uuid)
    }

    /// A filled tunnel for previews. Nothing here talks to a server.
    func present(_ tunnel: CloudflareTunnel) {
        self.tunnel = tunnel
        hasLoaded = true
        error = nil
    }

    private func change(to enabled: Bool, client: CoolifyClient, server uuid: String) async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        do {
            if enabled {
                tunnel = try await client.enableCloudflareTunnel(uuid: uuid)
            } else {
                tunnel = try await client.disableCloudflareTunnel(uuid: uuid)
            }
            hasLoaded = true
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        (error as? CoolifyError)?.summary ?? error.localizedDescription
    }
}

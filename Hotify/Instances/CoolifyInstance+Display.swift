import CoolifyAPI
import Foundation

extension CoolifyInstance {
    /// The host and port without the scheme, such as `coolify.example.com` or `10.0.0.4:8000`.
    var displayHost: String {
        guard let host = baseURL.host() else { return baseURL.absoluteString }
        if let port = baseURL.port {
            return "\(host):\(port)"
        }
        return host
    }
}

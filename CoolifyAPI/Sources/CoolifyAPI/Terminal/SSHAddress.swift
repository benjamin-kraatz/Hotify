import Foundation

/// Where a server answers SSH from this device.
public struct SSHAddress: Hashable, Codable, Sendable {
    public var host: String
    public var port: Int

    public init(host: String, port: Int = 22) {
        self.host = host
        self.port = port
    }
}

extension Server {
    /// The address Coolify connects to, unless only Coolify's container can use it.
    ///
    /// The server Coolify runs on reports `host.docker.internal` or `localhost`, which only mean something inside
    /// Coolify's container. That server gets the instance's own host instead. `nil` when neither gives a host.
    public func sshAddress(instanceURL: URL) -> SSHAddress? {
        let port = port.flatMap { $0 > 0 ? $0 : nil } ?? 22
        let ip = ip?.trimmingCharacters(in: .whitespaces) ?? ""
        if ip.isEmpty || Self.containerOnlyHosts.contains(ip.lowercased()) {
            guard let host = instanceURL.host(), !host.isEmpty else { return nil }
            return SSHAddress(host: host, port: port)
        }
        return SSHAddress(host: ip, port: port)
    }

    /// The user Coolify signs in as. Coolify treats a server without one as root.
    public var sshUser: String {
        guard let user = user?.trimmingCharacters(in: .whitespaces), !user.isEmpty else { return "root" }
        return user
    }

    /// Coolify runs Docker through sudo for any user but root.
    public var needsSudo: Bool { sshUser != "root" }

    private static let containerOnlyHosts: Set<String> = ["host.docker.internal", "localhost", "127.0.0.1", "::1"]
}

import CryptoKit
import Foundation
import NIOSSH

/// The key a server proved its identity with, in the form `ssh-ed25519 AAAA…`, as in `known_hosts`.
public struct SSHHostKey: Hashable, Codable, Sendable {
    public var openSSH: String

    public init(openSSH: String) {
        self.openSSH = openSSH.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(_ key: NIOSSHPublicKey) {
        self.init(openSSH: String(openSSHPublicKey: key))
    }

    /// The key type, such as `ssh-ed25519`.
    public var algorithm: String {
        openSSH.split(separator: " ").first.map(String.init) ?? ""
    }

    /// `SHA256:…`, the same fingerprint `ssh` and `ssh-keygen -l` print.
    public var fingerprint: String {
        let parts = openSSH.split(separator: " ")
        guard parts.count >= 2, let blob = Data(base64Encoded: String(parts[1])) else { return openSSH }
        let digest = Data(SHA256.hash(data: blob)).base64EncodedString()
        return "SHA256:" + digest.trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}

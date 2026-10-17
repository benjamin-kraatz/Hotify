import CryptoKit
import Foundation
import NIOSSH

/// The ed25519 key a connection signs in with.
public struct SSHIdentity: Sendable {
    let key: Curve25519.Signing.PrivateKey

    public init(ed25519 key: Curve25519.Signing.PrivateKey) {
        self.key = key
    }

    /// Reads an unencrypted ed25519 key in OpenSSH's format. Throws `SSHKeyError` for anything else.
    public init(openSSHPrivateKey text: String) throws {
        key = try OpenSSHPrivateKey.ed25519(from: text)
    }

    /// The line for `authorized_keys`, such as `ssh-ed25519 AAAA… hotify-mac`.
    public func publicKeyLine(comment: String) -> String {
        let line = String(openSSHPublicKey: privateKey.publicKey)
        return comment.isEmpty ? line : line + " " + comment
    }

    var privateKey: NIOSSHPrivateKey { NIOSSHPrivateKey(ed25519Key: key) }
}

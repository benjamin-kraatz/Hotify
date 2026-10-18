import Foundation

/// Why a connection or a session didn't come up, or ended.
public enum SSHConnectionError: Error, Equatable, Sendable {
    /// The server presented a key nobody has trusted yet.
    case hostKeyUnknown(SSHHostKey)
    /// The server presented a different key than the one trusted before.
    case hostKeyChanged(presented: SSHHostKey, trusted: SSHHostKey)
    /// The server turned down the key.
    case authenticationFailed
    /// The server couldn't be reached, with the system's reason.
    case unreachable(String)
    /// No answer in time.
    case timedOut
    /// The server refused to open a session or run the command.
    case channelRejected
    /// The connection dropped.
    case closed
}

/// Why a private key can't be used.
public enum SSHKeyError: Error, Equatable, Sendable {
    /// Not an OpenSSH private key.
    case unreadable
    /// The key has a passphrase.
    case encrypted
    /// A key type other than ed25519, such as `ssh-rsa`.
    case unsupportedType(String)
}

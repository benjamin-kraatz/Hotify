import CryptoKit
import Foundation

/// Reads an unencrypted ed25519 key in OpenSSH's own format, the `-----BEGIN OPENSSH PRIVATE KEY-----` block that
/// `ssh-keygen` writes and Coolify stores.
enum OpenSSHPrivateKey {
    private static let header = "-----BEGIN OPENSSH PRIVATE KEY-----"
    private static let footer = "-----END OPENSSH PRIVATE KEY-----"
    private static let magic = Array("openssh-key-v1\0".utf8)

    static func ed25519(from text: String) throws -> Curve25519.Signing.PrivateKey {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(header), trimmed.hasSuffix(footer) else { throw SSHKeyError.unreadable }
        let body = trimmed.dropFirst(header.count).dropLast(footer.count).filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: String(body)) else { throw SSHKeyError.unreadable }

        var reader = Reader(buffer: Array(data))
        guard reader.take(magic.count) == magic else { throw SSHKeyError.unreadable }
        let cipher = try reader.string()
        let kdf = try reader.string()
        _ = try reader.bytes()
        guard cipher == "none", kdf == "none" else { throw SSHKeyError.encrypted }
        guard try reader.uint32() == 1 else { throw SSHKeyError.unreadable }
        _ = try reader.bytes()

        var secret = Reader(buffer: try reader.bytes())
        guard try secret.uint32() == secret.uint32() else { throw SSHKeyError.unreadable }
        let type = try secret.string()
        guard type == "ssh-ed25519" else { throw SSHKeyError.unsupportedType(type) }
        _ = try secret.bytes()
        // OpenSSH stores the 32-byte seed followed by the 32-byte public key.
        let pair = try secret.bytes()
        guard pair.count == 64 else { throw SSHKeyError.unreadable }
        do {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: pair.prefix(32))
        } catch {
            throw SSHKeyError.unreadable
        }
    }

    private struct Reader {
        var buffer: [UInt8]
        var offset = 0

        mutating func take(_ count: Int) -> [UInt8]? {
            guard count >= 0, offset + count <= buffer.count else { return nil }
            defer { offset += count }
            return Array(buffer[offset..<offset + count])
        }

        mutating func uint32() throws -> UInt32 {
            guard let raw = take(4) else { throw SSHKeyError.unreadable }
            return raw.reduce(0) { $0 << 8 | UInt32($1) }
        }

        mutating func bytes() throws -> [UInt8] {
            let count = try uint32()
            guard let value = take(Int(count)) else { throw SSHKeyError.unreadable }
            return value
        }

        mutating func string() throws -> String {
            String(decoding: try bytes(), as: UTF8.self)
        }
    }
}

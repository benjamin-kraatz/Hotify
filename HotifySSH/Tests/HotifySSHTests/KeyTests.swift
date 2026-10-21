import CryptoKit
import Foundation
import XCTest

@testable import HotifySSH

/// Checks key handling against what `ssh-keygen` writes and prints, since that's the format Coolify stores.
final class KeyTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "hotify-ssh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testReadsAnEd25519KeyFromSSHKeygen() throws {
        let key = try generate(type: "ed25519", passphrase: "")
        let identity = try SSHIdentity(openSSHPrivateKey: key.privateKey)
        XCTAssertEqual(identity.publicKeyLine(comment: "test@hotify"), key.publicKey)
    }

    func testRejectsAPassphrase() throws {
        let key = try generate(type: "ed25519", passphrase: "secret")
        XCTAssertThrowsError(try SSHIdentity(openSSHPrivateKey: key.privateKey)) { error in
            XCTAssertEqual(error as? SSHKeyError, .encrypted)
        }
    }

    func testRejectsRSA() throws {
        let key = try generate(type: "rsa", passphrase: "")
        XCTAssertThrowsError(try SSHIdentity(openSSHPrivateKey: key.privateKey)) { error in
            XCTAssertEqual(error as? SSHKeyError, .unsupportedType("ssh-rsa"))
        }
    }

    func testRejectsText() {
        XCTAssertThrowsError(try SSHIdentity(openSSHPrivateKey: "not a key")) { error in
            XCTAssertEqual(error as? SSHKeyError, .unreadable)
        }
    }

    func testFingerprintMatchesSSHKeygen() throws {
        let key = try generate(type: "ed25519", passphrase: "")
        let printed = try run("/usr/bin/ssh-keygen", ["-l", "-E", "sha256", "-f", key.publicKeyPath])
        let expected = try XCTUnwrap(printed.split(separator: " ").dropFirst().first.map(String.init))
        XCTAssertEqual(SSHHostKey(openSSH: key.publicKey).fingerprint, expected)
        XCTAssertEqual(SSHHostKey(openSSH: key.publicKey).algorithm, "ssh-ed25519")
    }

    func testGeneratedKeyHasALine() {
        let identity = SSHIdentity(ed25519: Curve25519.Signing.PrivateKey())
        let line = identity.publicKeyLine(comment: "hotify-mac")
        XCTAssertTrue(line.hasPrefix("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5"))
        XCTAssertTrue(line.hasSuffix(" hotify-mac"))
    }

    private func generate(type: String, passphrase: String) throws -> (
        privateKey: String, publicKey: String, publicKeyPath: String
    ) {
        let path = directory.appending(path: "key-\(type)-\(passphrase.isEmpty ? "plain" : "locked")").path()
        _ = try run(
            "/usr/bin/ssh-keygen", ["-q", "-t", type, "-N", passphrase, "-C", "test@hotify", "-f", path])
        let privateKey = try String(contentsOfFile: path, encoding: .utf8)
        let publicKey = try String(contentsOfFile: path + ".pub", encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (privateKey, publicKey, path + ".pub")
    }

    private func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}

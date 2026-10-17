import CryptoKit
import Foundation
import XCTest

@testable import HotifySSH

/// Runs the connection against the server in `TestServer.swift`: host key checks, commands, terminals, and probes.
final class ConnectionTests: XCTestCase {
    private var server: TestServer!
    private let identity = SSHIdentity(ed25519: Curve25519.Signing.PrivateKey())

    override func setUp() async throws {
        server = try await TestServer.start()
    }

    override func tearDown() async throws {
        await server.stop()
    }

    private func open(trusting trusted: SSHHostKey? = nil) async throws -> SSHConnection {
        try await SSHConnection.open(
            host: "127.0.0.1", port: server.port, user: "root", identity: identity, trusting: trusted ?? server.hostKey
        )
    }

    func testReportsAnUnknownHostKeyThenConnectsOnceTrusted() async throws {
        do {
            _ = try await SSHConnection.open(
                host: "127.0.0.1", port: server.port, user: "root", identity: identity, trusting: nil)
            XCTFail("Connected without a trusted key")
        } catch let error as SSHConnectionError {
            XCTAssertEqual(error, .hostKeyUnknown(server.hostKey))
        }
        let connection = try await open()
        await connection.close()
    }

    func testRefusesAChangedHostKey() async throws {
        let stale = SSHHostKey(
            openSSH: SSHIdentity(ed25519: Curve25519.Signing.PrivateKey()).publicKeyLine(comment: ""))
        do {
            _ = try await open(trusting: stale)
            XCTFail("Connected with the wrong key trusted")
        } catch let error as SSHConnectionError {
            XCTAssertEqual(error, .hostKeyChanged(presented: server.hostKey, trusted: stale))
        }
    }

    func testRunsACommandAndReadsItsExitStatus() async throws {
        let connection = try await open()
        let result = try await connection.run("docker ps")
        XCTAssertEqual(result.output, "docker ps")
        XCTAssertEqual(result.exitStatus, TestServer.exitStatus)
        await connection.close()
    }

    func testTerminalCarriesItsSizeAndEnds() async throws {
        let connection = try await open()
        let terminal = try await connection.openTerminal("sh", columns: 120, rows: 40)
        var bytes: [UInt8] = []
        var status: Int?
        for await output in terminal.output {
            switch output {
            case .bytes(let more): bytes += more
            case .exited(let code): status = code
            }
        }
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), "120x40 sh")
        XCTAssertEqual(status, TestServer.exitStatus)
        await connection.close()
    }

    func testProbeMeasuresARoundTrip() async throws {
        let connection = try await open()
        let roundTrip = try await connection.probe(timeout: .seconds(5))
        XCTAssertGreaterThan(roundTrip, .zero)
        XCTAssertLessThan(roundTrip, .seconds(5))
        await connection.close()
    }

    func testProbeFailsOnceClosed() async throws {
        let connection = try await open()
        await connection.close()
        do {
            _ = try await connection.probe(timeout: .seconds(1))
            XCTFail("Probed a closed connection")
        } catch let error as SSHConnectionError {
            XCTAssertEqual(error, .closed)
        }
    }

    func testKeepAliveYieldsRoundTripsWhileTheServerAnswers() async throws {
        let connection = try await open()
        var roundTrips: [Duration] = []
        for await roundTrip in connection.keepAlive(every: .milliseconds(20), timeout: .seconds(2)) {
            roundTrips.append(roundTrip)
            if roundTrips.count == 3 {
                break
            }
        }
        XCTAssertEqual(roundTrips.count, 3)
        await connection.close()
    }

    func testKeepAliveClosesAConnectionThatStopsAnswering() async throws {
        await server.stop()
        server = try await TestServer.start(answersProbes: false)
        let connection = try await open()
        var roundTrips = 0
        for await _ in connection.keepAlive(every: .milliseconds(20), timeout: .milliseconds(300)) {
            roundTrips += 1
        }
        XCTAssertEqual(roundTrips, 0)
        await connection.waitUntilClosed()
        do {
            _ = try await connection.run("true")
            XCTFail("Ran a command on a dead connection")
        } catch {}
    }
}

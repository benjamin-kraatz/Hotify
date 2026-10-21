import Foundation
import XCTest

@testable import CoolifyAPI

final class TerminalTests: XCTestCase {
    func testServerSettingsDecodeTerminalAndTunnelDigits() throws {
        let json = #"{"uuid":"s1","name":"edge","settings":{"is_terminal_enabled":0,"is_cloudflare_tunnel":"1"}}"#
        let server = try CoolifyJSON.decoder().decode(Server.self, from: Data(json.utf8))
        XCTAssertEqual(server.settings?.isTerminalEnabled, false)
        XCTAssertEqual(server.settings?.isCloudflareTunnel, true)
    }

    func testPrivateKeyMaterialRequestAndRedaction() async throws {
        let client = try makeTerminalClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path(percentEncoded: true), "/api/v1/security/keys/key%201")
            XCTAssertNil(request.httpBody)
            return (200, Data(#"{"uuid":"key 1","name":"Coolify","private_key":"MATERIAL\n"}"#.utf8), [:])
        }
        let key = try await client.privateKeyMaterial(uuid: "key 1")
        XCTAssertEqual(key.privateKey, "MATERIAL")
        XCTAssertFalse(key.description.contains("MATERIAL"))
    }

    func testPrivateKeyMaterialWithheld() throws {
        let decoder = CoolifyJSON.decoder()
        let empty = try decoder.decode(PrivateKeyMaterial.self, from: Data(#"{"uuid":"k","private_key":""}"#.utf8))
        XCTAssertNil(empty.privateKey)
        let missing = try decoder.decode(PrivateKeyMaterial.self, from: Data(#"{"uuid":"k"}"#.utf8))
        XCTAssertNil(missing.privateKey)
    }

    func testApplicationLookupCommand() {
        let lookup = ContainerLookup(owner: .application, uuid: "abc123", usesSudo: false)
        XCTAssertEqual(
            lookup.command,
            "docker ps --format '{{json .}}' --filter 'label=coolify.applicationUuid=abc123'; "
                + "docker ps --format '{{json .}}' --filter 'label=coolify.applicationId' "
                + "--filter 'label=com.docker.compose.project=abc123'; "
                + "docker ps --format '{{json .}}' --filter 'label=coolify.applicationId' --filter 'name=abc123'"
        )
    }

    func testServiceAndDatabaseLookupCommandsWithSudo() {
        let service = ContainerLookup(owner: .service, uuid: "svc", usesSudo: true).command
        XCTAssertEqual(
            service,
            "sudo docker ps --format '{{json .}}' --filter 'label=coolify.serviceUuid=svc'; "
                + "sudo docker ps --format '{{json .}}' --filter 'label=coolify.serviceId' "
                + "--filter 'label=com.docker.compose.project=svc'"
        )
        let database = ContainerLookup(owner: .database, uuid: "db", usesSudo: false).command
        XCTAssertTrue(database.hasSuffix("; docker ps --format '{{json .}}' --filter 'name=db'"))
        XCTAssertTrue(database.hasPrefix("docker ps --format '{{json .}}' --filter 'label=coolify.databaseUuid=db'"))
    }

    func testLookupMergesAndFiltersPreviews() {
        let output = """
            sudo: unable to resolve host edge
            {"ID":"a1","Names":"abc123-120000","Image":"app:latest","State":"running","Status":"Up 2 hours",\
            "Labels":"coolify.applicationId=4,coolify.pullRequestId=0,traefik.http.routers.r.rule=Host(`a.example`,`b.example`)"}
            {"ID":"p7","Names":"abc123-pr-7","State":"running","Labels":"coolify.applicationId=4,coolify.pullRequestId=7"}
            {"ID":"a1","Names":"abc123-120000","State":"running","Labels":"coolify.applicationId=4"}
            {"ID":"old","Names":"abc123,legacy-link","State":"running","Labels":"coolify.applicationId=4"}
            """
        let production = ContainerLookup(owner: .application, uuid: "abc123", usesSudo: false)
        let found = production.containers(in: output)
        XCTAssertEqual(found.map(\.id), ["a1", "old"])
        XCTAssertEqual(found[0].labels["traefik.http.routers.r.rule"], "Host(`a.example`,`b.example`)")
        XCTAssertEqual(found[0].status, "Up 2 hours")
        XCTAssertEqual(found[1].name, "abc123")

        let preview = ContainerLookup(owner: .application, uuid: "abc123", pullRequest: 7, usesSudo: false)
        XCTAssertEqual(preview.containers(in: output).map(\.id), ["p7"])
    }

    func testShellInContainerQuotesTheName() {
        XCTAssertEqual(
            TerminalCommand.shell(inContainer: "web-o'brien", usesSudo: true),
            "sudo docker exec -it 'web-o'\\''brien' sh -c "
                + "'PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin && "
                + "if [ -f ~/.profile ]; then . ~/.profile; fi && "
                + "if [ -n \"$SHELL\" ] && [ -x \"$SHELL\" ]; then exec $SHELL; else sh; fi'"
        )
    }

    func testInstallKeyAddsTheLineOnce() {
        let line = "ssh-ed25519 AAAAC3Nz hotify-mac"
        XCTAssertEqual(
            TerminalCommand.installKey(line),
            "umask 077 && mkdir -p ~/.ssh && touch ~/.ssh/authorized_keys && "
                + #"if [ -s ~/.ssh/authorized_keys ] && [ -n "$(tail -c1 ~/.ssh/authorized_keys)" ]; "#
                + "then echo >> ~/.ssh/authorized_keys; fi && "
                + "grep -qxF 'ssh-ed25519 AAAAC3Nz hotify-mac' ~/.ssh/authorized_keys "
                + "|| echo 'ssh-ed25519 AAAAC3Nz hotify-mac' >> ~/.ssh/authorized_keys"
        )
        XCTAssertEqual(
            TerminalCommand.addKeyByHand(line),
            "echo 'ssh-ed25519 AAAAC3Nz hotify-mac' >> ~/.ssh/authorized_keys"
        )
    }

    func testSSHAddressUsesTheInstanceHostForCoolifysOwnServer() throws {
        let instance = try XCTUnwrap(URL(string: "https://coolify.example.com:8443/api/v1"))
        let decoder = CoolifyJSON.decoder()
        let local = try decoder.decode(
            Server.self,
            from: Data(
                #"{"uuid":"s0","name":"localhost","ip":"host.docker.internal","port":"22","user":"root","is_coolify_host":1}"#
                    .utf8)
        )
        XCTAssertEqual(local.sshAddress(instanceURL: instance), SSHAddress(host: "coolify.example.com", port: 22))
        XCTAssertFalse(local.needsSudo)

        let remote = try decoder.decode(
            Server.self, from: Data(#"{"uuid":"s1","name":"edge","ip":"203.0.113.9","port":2222,"user":"deploy"}"#.utf8)
        )
        XCTAssertEqual(remote.sshAddress(instanceURL: instance), SSHAddress(host: "203.0.113.9", port: 2222))
        XCTAssertEqual(remote.sshUser, "deploy")
        XCTAssertTrue(remote.needsSudo)

        let bare = Server(uuid: "s2", name: "bare", ip: "198.51.100.4")
        XCTAssertEqual(bare.sshAddress(instanceURL: instance), SSHAddress(host: "198.51.100.4", port: 22))
        XCTAssertEqual(bare.sshUser, "root")
    }
}

private func makeTerminalClient(
    responder: @escaping @Sendable (URLRequest) throws -> (Int, Data, [String: String])
) throws -> CoolifyClient {
    TerminalURLProtocol.responder = responder
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [TerminalURLProtocol.self]
    return try CoolifyClient(
        instanceURL: "http://coolify.example:8000",
        token: "test-token",
        session: URLSession(configuration: configuration)
    )
}

private final class TerminalURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responder: (@Sendable (URLRequest) throws -> (Int, Data, [String: String]))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let responder = Self.responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (status, data, headers) = try responder(request)
            guard let url = request.url,
                let response = HTTPURLResponse(
                    url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

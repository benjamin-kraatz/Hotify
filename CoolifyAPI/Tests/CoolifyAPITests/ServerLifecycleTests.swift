import Foundation
import XCTest

@testable import CoolifyAPI

final class ServerLifecycleTests: XCTestCase {
    func testCreateServerOmitsNilDescriptionAndSendsTheKeyUUID() async throws {
        let client = try makeLifecycleClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/servers")
            let body = jsonBody(request)
            XCTAssertNil(body?["description"])
            XCTAssertEqual(body?["private_key_uuid"] as? String, "key-1")
            XCTAssertEqual(
                body,
                [
                    "name": "edge",
                    "ip": "10.0.0.8",
                    "port": 22,
                    "user": "root",
                    "private_key_uuid": "key-1",
                    "is_build_server": false,
                    "instant_validate": true,
                ] as NSDictionary)
            return (201, Data(#"{"uuid":"server-9"}"#.utf8), [:])
        }
        let created = try await client.createServer(
            ServerDraft(
                name: "edge",
                ip: "10.0.0.8",
                port: 22,
                user: "root",
                privateKeyUUID: "key-1",
                isBuildServer: false,
                instantValidate: true
            ))
        XCTAssertEqual(created.uuid, "server-9")
    }

    func testUpdateServerOmitsAbsentCapacityFields() async throws {
        let minimal = try makeLifecycleClient { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/servers/server-1")
            let body = jsonBody(request)
            XCTAssertNil(body?["concurrent_builds"])
            XCTAssertNil(body?["dynamic_timeout"])
            XCTAssertNil(body?["deployment_queue_limit"])
            XCTAssertNil(body?["server_disk_usage_notification_threshold"])
            XCTAssertNil(body?["server_disk_usage_check_frequency"])
            XCTAssertNil(body?["connection_timeout"])
            XCTAssertEqual(
                body,
                [
                    "name": "edge",
                    "private_key_uuid": "key-1",
                ] as NSDictionary)
            return (200, Data(#"{"uuid":"server-1","name":"edge"}"#.utf8), [:])
        }
        let updated = try await minimal.updateServer(
            "server-1",
            ServerUpdate(name: "edge", privateKeyUUID: "key-1")
        )
        XCTAssertEqual(updated.uuid, "server-1")
        XCTAssertEqual(updated.name, "edge")

        let full = try makeLifecycleClient { request in
            XCTAssertEqual(
                jsonBody(request),
                [
                    "name": "edge",
                    "concurrent_builds": 2,
                    "dynamic_timeout": 3600,
                    "deployment_queue_limit": 5,
                    "server_disk_usage_notification_threshold": 80,
                    "server_disk_usage_check_frequency": "0 23 * * *",
                    "connection_timeout": 10,
                ] as NSDictionary)
            return (200, Data(#"{"uuid":"server-1","name":"edge"}"#.utf8), [:])
        }
        _ = try await full.updateServer(
            "server-1",
            ServerUpdate(
                name: "edge",
                concurrentBuilds: 2,
                dynamicTimeout: 3600,
                deploymentQueueLimit: 5,
                serverDiskUsageNotificationThreshold: 80,
                serverDiskUsageCheckFrequency: "0 23 * * *",
                connectionTimeout: 10
            ))
    }

    func testDeleteServerPath() async throws {
        let client = try makeLifecycleClient { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/api/v1/servers/server-1")
            XCTAssertNil(bodyText(request))
            return (200, Data(#"{"message":"Server deleted."}"#.utf8), [:])
        }
        let action = try await client.deleteServer("server-1")
        XCTAssertEqual(action.message, "Server deleted.")
    }

    func testCreatePrivateKeySendsTheKeyAndDoesNotPrintIt() async throws {
        let material = "fixture-key-material"
        let draft = PrivateKeyDraft(name: "lab", privateKey: material)
        let client = try makeLifecycleClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/security/keys")
            let body = jsonBody(request)
            XCTAssertEqual(body?["private_key"] as? String, material)
            XCTAssertEqual(body?["name"] as? String, "lab")
            XCTAssertNil(body?["description"])
            return (201, Data(#"{"uuid":"key-9"}"#.utf8), [:])
        }
        let created = try await client.createPrivateKey(draft)
        XCTAssertEqual(created.uuid, "key-9")
        XCTAssertFalse(String(describing: draft).contains(material))
        XCTAssertFalse(String(reflecting: draft).contains(material))
    }

    func testPrivateKeysIgnoreTheKeyMaterial() async throws {
        let material = "fixture-key-material"
        let client = try makeLifecycleClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/security/keys")
            let body = """
                [{
                  "uuid": "key-1",
                  "name": "lab",
                  "private_key": "\(material)",
                  "public_key": "ssh-ed25519 AAAA",
                  "is_git_related": 1
                }]
                """
            return (200, Data(body.utf8), [:])
        }
        let keys = try await client.privateKeys()
        XCTAssertEqual(keys.map(\.uuid), ["key-1"])
        XCTAssertEqual(keys.first?.name, "lab")
        XCTAssertFalse(String(describing: keys.first).contains(material))
    }

    func testServerDetailDecodesCapacityAndIgnoresKeyMaterial() throws {
        let material = "fixture-key-material"
        let json = """
            {
              "uuid": "server-1",
              "name": "edge",
              "description": "Lab",
              "ip": "10.0.0.8",
              "port": "22",
              "user": "root",
              "private_key": {
                "uuid": "key-1",
                "name": "lab",
                "private_key": "\(material)"
              },
              "server_disk_usage_notification_threshold": "80",
              "server_disk_usage_check_frequency": "0 23 * * *",
              "settings": {
                "is_build_server": 0,
                "is_reachable": 1,
                "concurrent_builds": "2",
                "dynamic_timeout": 3600,
                "deployment_queue_limit": 5,
                "connection_timeout": "10"
              }
            }
            """
        let server = try CoolifyJSON.decoder().decode(Server.self, from: Data(json.utf8))
        XCTAssertEqual(server.uuid, "server-1")
        XCTAssertEqual(server.description, "Lab")
        XCTAssertEqual(server.port, 22)
        XCTAssertEqual(server.user, "root")
        XCTAssertEqual(server.privateKeyUUID, "key-1")
        XCTAssertEqual(server.serverDiskUsageNotificationThreshold, 80)
        XCTAssertEqual(server.serverDiskUsageCheckFrequency, "0 23 * * *")
        XCTAssertEqual(server.settings?.isBuildServer, false)
        XCTAssertEqual(server.settings?.isReachable, true)
        XCTAssertEqual(server.settings?.concurrentBuilds, 2)
        XCTAssertEqual(server.settings?.dynamicTimeout, 3600)
        XCTAssertEqual(server.settings?.deploymentQueueLimit, 5)
        XCTAssertEqual(server.settings?.connectionTimeout, 10)
        XCTAssertFalse(String(describing: server).contains(material))
    }
}

private func jsonBody(_ request: URLRequest) -> NSDictionary? {
    guard let text = bodyText(request) else { return nil }
    return try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? NSDictionary
}

/// URLSession hands a protocol the body as a stream, not as `httpBody`.
private func bodyText(_ request: URLRequest) -> String? {
    if let body = request.httpBody {
        return String(decoding: body, as: UTF8.self)
    }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: buffer.count)
        guard read > 0 else { break }
        data.append(buffer, count: read)
    }
    return String(decoding: data, as: UTF8.self)
}

private func makeLifecycleClient(
    responder: @escaping @Sendable (URLRequest) throws -> (Int, Data, [String: String])
) throws -> CoolifyClient {
    ServerLifecycleURLProtocol.responder = responder
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ServerLifecycleURLProtocol.self]
    return try CoolifyClient(
        instanceURL: "http://coolify.example:8000",
        token: "test-token",
        session: URLSession(configuration: configuration)
    )
}

private final class ServerLifecycleURLProtocol: URLProtocol, @unchecked Sendable {
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

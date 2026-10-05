import Foundation
import XCTest

@testable import CoolifyAPI

final class ServerMaintenanceTests: XCTestCase {
    func testValidatePostsInstallFalse() async throws {
        let client = try makeServerClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/servers/server-1/validate")
            XCTAssertEqual(jsonBody(request), ["install": false] as NSDictionary?)
            return (201, Data(#"{"message":"Validation started."}"#.utf8), [:])
        }
        let action = try await client.validateServer(uuid: "server-1")
        XCTAssertEqual(action.message, "Validation started.")
    }

    func testValidatePostsInstallTrue() async throws {
        let client = try makeServerClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/servers/server-1/validate")
            XCTAssertEqual(jsonBody(request), ["install": true] as NSDictionary?)
            return (201, Data(#"{"message":"Validation started."}"#.utf8), [:])
        }
        let action = try await client.validateServer(uuid: "server-1", install: true)
        XCTAssertEqual(action.message, "Validation started.")
    }

    func testUpdateDockerCleanupOmitsNilBools() async throws {
        let client = try makeServerClient { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/servers/server-1/docker-cleanup")
            XCTAssertEqual(
                jsonBody(request),
                [
                    "docker_cleanup_frequency": "0 3 * * *",
                    "force_docker_cleanup": true,
                    "delete_unused_networks": false,
                ] as NSDictionary?
            )
            return (
                200,
                Data(
                    #"{"docker_cleanup_frequency":"0 3 * * *","force_docker_cleanup":1,"delete_unused_networks":0}"#
                        .utf8),
                [:]
            )
        }
        let updated = try await client.updateDockerCleanup(
            uuid: "server-1",
            settings: DockerCleanupSettings(
                dockerCleanupFrequency: "0 3 * * *",
                forceDockerCleanup: true,
                deleteUnusedNetworks: false
            )
        )
        XCTAssertEqual(updated.forceDockerCleanup, true)
        XCTAssertEqual(updated.deleteUnusedNetworks, false)
        XCTAssertNil(updated.deleteUnusedVolumes)
    }

    func testRunDockerCleanupPostsFlags() async throws {
        let client = try makeServerClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/servers/server-1/docker-cleanup/run")
            XCTAssertEqual(jsonBody(request), ["delete_unused_volumes": true] as NSDictionary?)
            return (200, Data(#"{"message":"Manual cleanup job started."}"#.utf8), [:])
        }
        let action = try await client.runDockerCleanup(uuid: "server-1", deleteUnusedVolumes: true)
        XCTAssertEqual(action.message, "Manual cleanup job started.")
    }

    func testRestartProxyPosts() async throws {
        let client = try makeServerClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/servers/server-1/proxy/restart")
            XCTAssertNil(bodyText(request))
            return (200, Data(#"{"message":"Proxy restart queued."}"#.utf8), [:])
        }
        let action = try await client.restartServerProxy(uuid: "server-1")
        XCTAssertEqual(action.message, "Proxy restart queued.")
    }

    func testDomainsDecode() async throws {
        let client = try makeServerClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/servers/server-1/domains")
            return (
                200,
                Data(
                    """
                    [{"ip":"10.0.0.8","domains":["app.example.com","api.example.com"]},
                     {"ip":"10.0.0.9","domains":[]}]
                    """.utf8
                ),
                [:]
            )
        }
        let groups = try await client.serverDomains(uuid: "server-1")
        XCTAssertEqual(groups.map(\.ip), ["10.0.0.8", "10.0.0.9"])
        XCTAssertEqual(groups[0].domains, ["app.example.com", "api.example.com"])
        XCTAssertEqual(groups[1].domains, [])
    }

    func testDockerCleanupDecodesBooleanDigits() async throws {
        let client = try makeServerClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/servers/server-1/docker-cleanup")
            return (
                200,
                Data(
                    """
                    {"docker_cleanup_frequency":"daily","docker_cleanup_threshold":"80",
                     "force_docker_cleanup":0,"delete_unused_volumes":1,
                     "delete_unused_networks":0,"disable_application_image_retention":1}
                    """.utf8),
                [:]
            )
        }
        let settings = try await client.dockerCleanup(uuid: "server-1")
        XCTAssertEqual(settings.dockerCleanupFrequency, "daily")
        XCTAssertEqual(settings.dockerCleanupThreshold, 80)
        XCTAssertEqual(settings.forceDockerCleanup, false)
        XCTAssertEqual(settings.deleteUnusedVolumes, true)
        XCTAssertEqual(settings.deleteUnusedNetworks, false)
        XCTAssertEqual(settings.disableApplicationImageRetention, true)
    }

    func testProxyIgnoresRawConfiguration() async throws {
        let json = """
            {"proxy_type":"TRAEFIK","status":"running","redirect_enabled":1,
             "redirect_url":"https://example.com",
             "configuration":"services:\\n  traefik:\\n    environment:\\n      - SECRET=token"}
            """
        let client = try makeServerClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/servers/server-1/proxy")
            return (200, Data(json.utf8), [:])
        }
        let proxy = try await client.serverProxy(uuid: "server-1")
        XCTAssertEqual(proxy.proxyType, "TRAEFIK")
        XCTAssertEqual(proxy.status, "running")
        XCTAssertEqual(proxy.redirectEnabled, true)
        XCTAssertEqual(proxy.redirectUrl, "https://example.com")
        let stored = Mirror(reflecting: proxy).children.map { "\($0.label ?? "")=\($0.value)" }.joined(separator: " ")
        XCTAssertFalse(stored.contains("SECRET"))
        XCTAssertFalse(stored.contains("configuration"))
    }

    func testCleanupExecutionsDecode() async throws {
        let client = try makeServerClient { request in
            XCTAssertEqual(request.url?.path, "/api/v1/servers/server-1/docker-cleanup/executions")
            return (
                200,
                Data(
                    """
                    [{"uuid":"run-1","status":"failed","message":"disk full",
                      "created_at":"2026-10-01T04:00:00Z","finished_at":"2026-10-01T04:02:00Z"}]
                    """.utf8
                ),
                [:]
            )
        }
        let runs = try await client.dockerCleanupExecutions(uuid: "server-1")
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].uuid, "run-1")
        XCTAssertEqual(runs[0].status, "failed")
        XCTAssertEqual(runs[0].message, "disk full")
        XCTAssertNotNil(runs[0].createdAtDate)
        XCTAssertNotNil(runs[0].finishedAtDate)
    }
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

private func jsonBody(_ request: URLRequest) -> NSDictionary? {
    guard let text = bodyText(request) else { return nil }
    return try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? NSDictionary
}

private func makeServerClient(
    responder: @escaping @Sendable (URLRequest) throws -> (Int, Data, [String: String])
) throws -> CoolifyClient {
    ServerMaintenanceURLProtocol.responder = responder
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ServerMaintenanceURLProtocol.self]
    return try CoolifyClient(
        instanceURL: "http://coolify.example:8000",
        token: "test-token",
        session: URLSession(configuration: configuration)
    )
}

private final class ServerMaintenanceURLProtocol: URLProtocol, @unchecked Sendable {
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

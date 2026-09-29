import Foundation
import XCTest
@testable import CoolifyAPI

final class CoolifyAPITests: XCTestCase {
    func testAPIBaseAcceptsInstanceRootAPIRootAndMCPURL() throws {
        let root = try CoolifyClient(instanceURL: "http://coolify.example:8000", token: "token")
        XCTAssertEqual(root.apiBaseURL.absoluteString, "http://coolify.example:8000/api/v1")

        let api = try CoolifyClient(instanceURL: "https://app.coolify.io/api/v1/", token: "token")
        XCTAssertEqual(api.apiBaseURL.absoluteString, "https://app.coolify.io/api/v1")

        let mcp = try CoolifyClient(instanceURL: "http://coolify.example:8000/mcp", token: "token")
        XCTAssertEqual(mcp.apiBaseURL.absoluteString, "http://coolify.example:8000/api/v1")
    }

    func testApplicationSettingsAcceptIntegerBooleans() throws {
        let json = """
        {
          "uuid": "app-1",
          "name": "Web",
          "status": "running:healthy",
          "git_repository": "git@github.com:example/web.git",
          "created_at": "2026-09-18T12:02:18.000000Z",
          "settings": { "is_preview_deployments_enabled": true, "is_force_https_enabled": 1 }
        }
        """.data(using: .utf8)!

        let application = try CoolifyJSON.decoder().decode(Application.self, from: json)
        XCTAssertEqual(application.settings?.isForceHTTPSEnabled, true)
        XCTAssertEqual(application.settings?.isPreviewDeploymentsEnabled, true)
        XCTAssertNotNil(application.createdAtDate)
    }

    func testDeploymentPageReadsStringPullRequestID() throws {
        let json = """
        {
          "count": 1,
          "deployments": [{
            "deployment_uuid": "dep-1",
            "pull_request_id": "18",
            "is_api": 1
          }]
        }
        """.data(using: .utf8)!

        let page = try CoolifyJSON.decoder().decode(DeploymentPage.self, from: json)
        XCTAssertEqual(page.deployments[0].pullRequestID, 18)
        XCTAssertTrue(page.deployments[0].isPreview)
        XCTAssertEqual(page.deployments[0].isAPI, true)
    }

    func testServiceDecodeKeepsNestedContainerStatus() throws {
        let json = """
        {
          "uuid": "svc-1",
          "name": "convex",
          "status": "running:healthy",
          "service_type": "convex",
          "server_status": true,
          "applications": [{
            "id": 7,
            "name": "dashboard",
            "human_name": "dashboard",
            "status": "running:healthy"
          }]
        }
        """.data(using: .utf8)!

        let service = try CoolifyJSON.decoder().decode(Service.self, from: json)
        XCTAssertEqual(service.applications?.first?.parsedStatus?.isRunning, true)
    }

    func testPreviewDeleteAndDeployUsePullRequestID() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            if request.httpMethod == "DELETE" {
                XCTAssertEqual(request.url?.path, "/api/v1/applications/app-1/previews/18")
                return (200, Data(#"{"message":"Preview deletion request queued."}"#.utf8), [:])
            }
            XCTAssertEqual(request.url?.path, "/api/v1/deploy")
            let query = request.url?.query ?? ""
            XCTAssertTrue(query.contains("uuid=app-1"))
            XCTAssertTrue(query.contains("pull_request_id=18"))
            let body = #"{"deployments":[{"message":"queued","resource_uuid":"app-1","deployment_uuid":"dep-2"}]}"#
            return (200, Data(body.utf8), [:])
        }

        let deleted = try await client.deletePreview(applicationUUID: "app-1", pullRequestID: 18)
        XCTAssertEqual(deleted.message, "Preview deletion request queued.")
        let started = try await client.startPreview(applicationUUID: "app-1", pullRequestID: 18)
        XCTAssertEqual(started.deployments.first?.deploymentUUID, "dep-2")
    }
}

private func makeClient(
    responder: @escaping @Sendable (URLRequest) throws -> (Int, Data, [String: String])
) throws -> CoolifyClient {
    MockURLProtocol.responder = responder
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return try CoolifyClient(instanceURL: "http://coolify.example:8000", token: "test-token", session: session)
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
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
                  let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
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

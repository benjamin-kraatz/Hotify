import Foundation
import XCTest

@testable import CoolifyAPI

final class ServiceContainerTests: XCTestCase {
    func testApplicationRestartAndDatabaseStop() async throws {
        let client = try makeServiceContainerClient { request in
            let method = request.httpMethod ?? ""
            let path = request.url?.path ?? ""
            XCTAssertNil(request.httpBody)
            switch (method, path) {
            case ("POST", "/api/v1/services/svc-1/applications/app-9/restart"):
                return (200, Data(#"{"message":"Restart request queued."}"#.utf8), [:])
            case ("POST", "/api/v1/services/svc-1/databases/db-3/stop"):
                return (200, Data(#"{"message":"Stop request queued."}"#.utf8), [:])
            case ("POST", "/api/v1/services/svc-1/applications/app-9/start"):
                return (200, Data(#"{"message":"Start request queued."}"#.utf8), [:])
            default:
                XCTFail("Unexpected \(method) \(path)")
                return (500, Data(), [:])
            }
        }

        let restarted = try await client.restartServiceContainer("svc-1", role: .application, uuid: "app-9")
        XCTAssertEqual(restarted.message, "Restart request queued.")
        let stopped = try await client.stopServiceContainer("svc-1", role: .database, uuid: "db-3")
        XCTAssertEqual(stopped.message, "Stop request queued.")
        _ = try await client.startServiceContainer("svc-1", role: .application, uuid: "app-9")
    }

    func testListPayloadDecodesUUIDAndNumericID() throws {
        let items = try CoolifyJSON.decoder().decode(
            [ServiceApplication].self,
            from: Data(
                """
                [{
                  "id": 12,
                  "uuid": "abc-1",
                  "name": "dashboard",
                  "status": "running:healthy",
                  "exclude_from_status": 1,
                  "extra": true
                }]
                """.utf8
            )
        )
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.id, 12)
        XCTAssertEqual(item.uuid, "abc-1")
        XCTAssertEqual(item.name, "dashboard")
        XCTAssertEqual(item.status, "running:healthy")
        XCTAssertEqual(item.excludeFromStatus, true)
    }

    func testItemWithoutUUIDDecodesEmpty() throws {
        let item = try CoolifyJSON.decoder().decode(
            ServiceApplication.self,
            from: Data(#"{"id":"4","name":"postgres","human_name":"Postgres"}"#.utf8)
        )
        XCTAssertEqual(item.id, 4)
        XCTAssertEqual(item.uuid, "")
        XCTAssertEqual(item.name, "postgres")
        XCTAssertEqual(item.humanName, "Postgres")
    }
}

private func makeServiceContainerClient(
    responder: @escaping @Sendable (URLRequest) throws -> (Int, Data, [String: String])
) throws -> CoolifyClient {
    ServiceContainerURLProtocol.responder = responder
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ServiceContainerURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return try CoolifyClient(instanceURL: "http://coolify.example:8000", token: "test-token", session: session)
}

private final class ServiceContainerURLProtocol: URLProtocol, @unchecked Sendable {
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

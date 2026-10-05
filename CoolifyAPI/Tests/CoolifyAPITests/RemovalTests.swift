import Foundation
import XCTest

@testable import CoolifyAPI

final class RemovalTests: XCTestCase {
    func testDeletesApplicationWithVolumesOffAndConfigurationsOn() async throws {
        let client = try makeRemovalClient { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(removalWire(request).contains("/api/v1/applications/app%2F1"))
            XCTAssertEqual(
                removalQuery(request),
                [
                    URLQueryItem(name: "delete_configurations", value: "true"),
                    URLQueryItem(name: "delete_volumes", value: "false"),
                    URLQueryItem(name: "docker_cleanup", value: "false"),
                    URLQueryItem(name: "delete_connected_networks", value: "false"),
                ]
            )
            return (200, Data(#"{"message":"Application deleted."}"#.utf8), [:])
        }
        let action = try await client.deleteApplication(
            "app/1",
            options: RemovalOptions(
                configurations: true, volumes: false, dockerCleanup: false, connectedNetworks: false)
        )
        XCTAssertEqual(action.message, "Application deleted.")
    }

    func testDeletesDatabase() async throws {
        let client = try makeRemovalClient { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(removalWire(request).contains("/api/v1/databases/db%2F9"))
            XCTAssertEqual(
                removalQuery(request),
                [
                    URLQueryItem(name: "delete_configurations", value: "false"),
                    URLQueryItem(name: "delete_volumes", value: "true"),
                    URLQueryItem(name: "docker_cleanup", value: "true"),
                    URLQueryItem(name: "delete_connected_networks", value: "true"),
                ]
            )
            return (200, Data(#"{"message":"Database deleted."}"#.utf8), [:])
        }
        let action = try await client.deleteDatabase(
            "db/9",
            options: RemovalOptions(
                configurations: false, volumes: true, dockerCleanup: true, connectedNetworks: true)
        )
        XCTAssertEqual(action.message, "Database deleted.")
    }

    func testDeletesProjectWithNoQuery() async throws {
        let client = try makeRemovalClient { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(removalWire(request).contains("/api/v1/projects/proj%2F1"))
            XCTAssertFalse(removalWire(request).contains("?"))
            XCTAssertTrue(removalQuery(request).isEmpty)
            return (200, Data(), [:])
        }
        let action = try await client.deleteProject("proj/1")
        XCTAssertNil(action.message)
        XCTAssertNil(action.deploymentUUID)
    }

    func testDeletesEnvironment() async throws {
        let client = try makeRemovalClient { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(removalWire(request).contains("/api/v1/projects/proj%2F1/environments/staging%2Fblue"))
            XCTAssertFalse(removalWire(request).contains("?"))
            XCTAssertTrue(removalQuery(request).isEmpty)
            return (200, Data(#"{"message":"Environment deleted."}"#.utf8), [:])
        }
        let action = try await client.deleteEnvironment("staging/blue", inProject: "proj/1")
        XCTAssertEqual(action.message, "Environment deleted.")
    }

    func testDeletesServiceWithoutForcingVolumes() async throws {
        let client = try makeRemovalClient { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(removalWire(request).contains("/api/v1/services/svc%2F1"))
            XCTAssertEqual(
                removalQuery(request),
                [
                    URLQueryItem(name: "delete_configurations", value: "true"),
                    URLQueryItem(name: "delete_volumes", value: "false"),
                    URLQueryItem(name: "docker_cleanup", value: "false"),
                    URLQueryItem(name: "delete_connected_networks", value: "false"),
                ]
            )
            // A message field that is not a string would throw a typed decode. A 2xx still succeeds.
            return (200, Data(#"{"message":1}"#.utf8), [:])
        }
        let action = try await client.deleteResource(
            "svc/1",
            kind: .service,
            options: RemovalOptions(configurations: true, volumes: false)
        )
        XCTAssertNil(action.message)
    }
}

private func makeRemovalClient(
    responder: @escaping @Sendable (URLRequest) throws -> (Int, Data, [String: String])
) throws -> CoolifyClient {
    RemovalFixtureProtocol.responder = responder
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RemovalFixtureProtocol.self]
    let session = URLSession(configuration: configuration)
    return try CoolifyClient(instanceURL: "http://coolify.example:8000", token: "test-token", session: session)
}

/// `URL.path` decodes `%2F`, which would hide the encoding. The request string keeps it.
private func removalWire(_ request: URLRequest) -> String {
    request.url?.absoluteString ?? ""
}

private func removalQuery(_ request: URLRequest) -> [URLQueryItem] {
    guard let url = request.url else { return [] }
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
}

private final class RemovalFixtureProtocol: URLProtocol, @unchecked Sendable {
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

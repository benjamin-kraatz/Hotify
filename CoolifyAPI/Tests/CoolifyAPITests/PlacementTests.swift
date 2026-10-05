import Foundation
import XCTest

@testable import CoolifyAPI

final class PlacementTests: XCTestCase {
    override func tearDown() {
        PlacementURLProtocol.responder = nil
        super.tearDown()
    }

    func testMovesApplicationWithOnlyTheEnvironment() async throws {
        let client = try makePlacementClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/applications/app-1/move")
            XCTAssertEqual(placementBody(request), #"{"environment_uuid":"env-2"}"#)
            let body =
                #"{"message":"Application moved successfully.","uuid":"app-1","#
                + #""project_uuid":"proj-1","environment_uuid":"env-2"}"#
            return (200, Data(body.utf8), [:])
        }
        let moved = try await client.moveResource(.application("app-1"), to: "env-2")
        XCTAssertEqual(moved.message, "Application moved successfully.")
        XCTAssertEqual(moved.uuid, "app-1")
        XCTAssertEqual(moved.projectUUID, "proj-1")
        XCTAssertEqual(moved.environmentUUID, "env-2")
    }

    func testClonesApplicationOmittingNilNameAndFalseVolumes() async throws {
        let client = try makePlacementClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/applications/app-1/clone")
            XCTAssertEqual(placementBody(request), #"{"destination_uuid":"dest-1"}"#)
            return (201, Data(#"{"uuid":"app-2","message":"Application cloned."}"#.utf8), [:])
        }
        let cloned = try await client.cloneResource(
            .application("app-1"), CloneResourceRequest(destinationUUID: "dest-1", name: nil, cloneVolumes: false))
        XCTAssertEqual(cloned.uuid, "app-2")
        XCTAssertEqual(cloned.message, "Application cloned.")
        _ = try await client.cloneResource(
            .application("app-1"), CloneResourceRequest(destinationUUID: "dest-1", name: "   ", cloneVolumes: nil))
    }

    func testMigratesServiceTransferringVolumes() async throws {
        let client = try makePlacementClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/services/svc-1/migrate")
            XCTAssertEqual(
                placementBody(request), #"{"destination_uuid":"dest-9","migrate_volumes":true}"#)
            return (200, Data(#"{"message":"Service migration started."}"#.utf8), [:])
        }
        let migrated = try await client.migrateResource(
            .service("svc-1"), MigrateResourceRequest(destinationUUID: "dest-9", migrateVolumes: true))
        XCTAssertEqual(migrated.message, "Service migration started.")
    }

    func testEachKindSharesItsPathPrefix() async throws {
        let client = try makePlacementClient { request in
            let path = request.url?.path ?? ""
            XCTAssertEqual(request.httpMethod, "POST")
            if path.hasSuffix("/move") {
                XCTAssertEqual(path, "/api/v1/databases/db-1/move")
                XCTAssertEqual(placementBody(request), #"{"environment_uuid":"env-9"}"#)
                return (200, Data(#"{"message":"Database moved successfully."}"#.utf8), [:])
            }
            if path.hasSuffix("/clone") {
                XCTAssertEqual(path, "/api/v1/services/svc-1/clone")
                XCTAssertEqual(
                    placementBody(request),
                    #"{"clone_volumes":true,"destination_uuid":"dest-2","name":"convex-copy"}"#)
                return (201, Data(#"{"uuid":"svc-2","message":"Service cloned."}"#.utf8), [:])
            }
            XCTAssertEqual(path, "/api/v1/applications/app-1/migrate")
            XCTAssertEqual(placementBody(request), #"{"destination_uuid":"dest-3"}"#)
            return (200, Data(), [:])
        }
        _ = try await client.moveResource(.database("db-1"), to: "env-9")
        _ = try await client.cloneResource(
            .service("svc-1"),
            CloneResourceRequest(destinationUUID: "dest-2", name: "convex-copy", cloneVolumes: true))
        let migrated = try await client.migrateResource(
            .application("app-1"), MigrateResourceRequest(destinationUUID: "dest-3", migrateVolumes: nil))
        XCTAssertNil(migrated.message)
    }

    func testPathEncodesTheUUID() {
        XCTAssertEqual(PlacementOwner.application("app/1").path("move"), "applications/app%2F1/move")
        XCTAssertEqual(PlacementOwner.database("db 1").path("clone"), "databases/db%201/clone")
        XCTAssertEqual(PlacementOwner.service("svc-1").path("migrate"), "services/svc-1/migrate")
    }

    func testMigrateSendsFalseWhenVolumesStayBehind() async throws {
        let client = try makePlacementClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/databases/db-1/migrate")
            XCTAssertEqual(
                placementBody(request), #"{"destination_uuid":"dest-1","migrate_volumes":false}"#)
            return (200, Data(), [:])
        }
        let migrated = try await client.migrateResource(
            .database("db-1"), MigrateResourceRequest(destinationUUID: "dest-1", migrateVolumes: false))
        XCTAssertNil(migrated.message)
    }
}

private func placementBody(_ request: URLRequest) -> String? {
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

private func makePlacementClient(
    responder: @escaping @Sendable (URLRequest) throws -> (Int, Data, [String: String])
) throws -> CoolifyClient {
    PlacementURLProtocol.responder = responder
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PlacementURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return try CoolifyClient(instanceURL: "http://coolify.example:8000", token: "test-token", session: session)
}

/// Answers move, clone, and migrate requests in tests. Not the suite's shared mock.
private final class PlacementURLProtocol: URLProtocol, @unchecked Sendable {
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

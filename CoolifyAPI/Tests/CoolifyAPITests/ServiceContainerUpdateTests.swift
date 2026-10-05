import Foundation
import XCTest

@testable import CoolifyAPI

final class ServiceContainerUpdateTests: XCTestCase {
    func testPatchApplicationSendsURLAndNameAndOmitsNilImage() async throws {
        let client = try makeServiceContainerUpdateClient { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/services/svc-1/applications/app-9")
            XCTAssertNil(request.url?.query)
            let object = try bodyObject(request)
            XCTAssertEqual(Set(object.keys), ["human_name", "url"])
            XCTAssertEqual(object["human_name"] as? String, "Dashboard")
            XCTAssertEqual(object["url"] as? String, "https://a.example.com,https://b.example.com")
            XCTAssertNil(object["image"])
            return (200, Data(#"{"uuid":"app-9"}"#.utf8), [:])
        }

        try await client.updateServiceApplication(
            "svc-1",
            uuid: "app-9",
            ServiceContainerApplicationUpdate(
                url: "https://a.example.com,https://b.example.com",
                humanName: "Dashboard",
                image: nil
            )
        )
    }

    func testPatchApplicationSendsForceDomainOverrideQuery() async throws {
        let client = try makeServiceContainerUpdateClient { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/services/svc-1/applications/app-9")
            let items = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(items, [URLQueryItem(name: "force_domain_override", value: "true")])
            let object = try bodyObject(request)
            XCTAssertEqual(object["url"] as? String, "https://taken.example.com")
            XCTAssertNil(object["force_domain_override"])
            return (200, Data(#"{"uuid":"app-9"}"#.utf8), [:])
        }

        try await client.updateServiceApplication(
            "svc-1",
            uuid: "app-9",
            ServiceContainerApplicationUpdate(url: "https://taken.example.com"),
            forceDomainOverride: true
        )
    }

    func testPatchDatabaseSendsPublicAccess() async throws {
        let client = try makeServiceContainerUpdateClient { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/services/svc-1/databases/db-3")
            XCTAssertNil(request.url?.query)
            let object = try bodyObject(request)
            XCTAssertEqual(Set(object.keys), ["is_public", "public_port"])
            XCTAssertEqual(jsonBool(object["is_public"]), true as Bool?)
            XCTAssertEqual(jsonInt(object["public_port"]), 5433 as Int?)
            return (200, Data(#"{"uuid":"db-3"}"#.utf8), [:])
        }

        try await client.updateServiceDatabase(
            "svc-1",
            uuid: "db-3",
            ServiceContainerDatabaseUpdate(isPublic: true, publicPort: 5433, publicPortTimeout: nil)
        )
    }
}

private func jsonBool(_ value: Any?) -> Bool? {
    if let value = value as? Bool { return value }
    if let value = value as? NSNumber { return value.boolValue }
    return nil
}

private func jsonInt(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    if let value = value as? NSNumber { return value.intValue }
    return nil
}

/// URLSession hands a protocol the body as a stream, not as `httpBody`.
private func bodyObject(_ request: URLRequest) throws -> [String: Any] {
    let data: Data
    if let body = request.httpBody {
        data = body
    } else if let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var loaded = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            loaded.append(buffer, count: read)
        }
        data = loaded
    } else {
        data = Data()
    }
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func makeServiceContainerUpdateClient(
    responder: @escaping @Sendable (URLRequest) throws -> (Int, Data, [String: String])
) throws -> CoolifyClient {
    ServiceContainerUpdateURLProtocol.responder = responder
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ServiceContainerUpdateURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return try CoolifyClient(instanceURL: "http://coolify.example:8000", token: "test-token", session: session)
}

private final class ServiceContainerUpdateURLProtocol: URLProtocol, @unchecked Sendable {
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

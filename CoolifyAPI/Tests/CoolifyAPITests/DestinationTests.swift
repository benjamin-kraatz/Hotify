import Foundation
import XCTest

@testable import CoolifyAPI

final class DestinationTests: XCTestCase {
    func testCreateDestinationPostsNetworkAndOmitsNilName() async throws {
        let client = try makeDestinationClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/servers/server-1/destinations")
            XCTAssertEqual(jsonObject(request), ["network": "coolify"] as NSDictionary?)
            return (201, Data(#"{"uuid":"dest-1","name":"coolify","network":"coolify"}"#.utf8), [:])
        }
        let created = try await client.createDestination(
            DestinationDraft(name: nil, network: "coolify", type: nil),
            onServer: "server-1"
        )
        XCTAssertEqual(created.uuid, "dest-1")
        XCTAssertEqual(created.name, "coolify")
        XCTAssertEqual(created.network, "coolify")
    }

    func testRenameDestinationPatchesOnlyName() async throws {
        let client = try makeDestinationClient { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/destinations/dest-1")
            XCTAssertEqual(jsonObject(request), ["name": "apps"] as NSDictionary?)
            return (200, Data(#"{"uuid":"dest-1","name":"apps","network":"coolify"}"#.utf8), [:])
        }
        let renamed = try await client.renameDestination("dest-1", name: "apps")
        XCTAssertEqual(renamed.name, "apps")
        XCTAssertEqual(renamed.network, "coolify")
    }

    func testDeleteDestinationPath() async throws {
        let client = try makeDestinationClient { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(
                request.url?.absoluteString,
                "http://coolify.example:8000/api/v1/destinations/dest%2F1"
            )
            XCTAssertNil(bodyText(request))
            return (200, Data(#"{"message":"Deleted."}"#.utf8), [:])
        }
        try await client.deleteDestination("dest/1")
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

private func jsonObject(_ request: URLRequest) -> NSDictionary? {
    guard let text = bodyText(request) else { return nil }
    return try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? NSDictionary
}

private func makeDestinationClient(
    responder: @escaping @Sendable (URLRequest) throws -> (Int, Data, [String: String])
) throws -> CoolifyClient {
    DestinationURLProtocol.responder = responder
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DestinationURLProtocol.self]
    return try CoolifyClient(
        instanceURL: "http://coolify.example:8000",
        token: "test-token",
        session: URLSession(configuration: configuration)
    )
}

private final class DestinationURLProtocol: URLProtocol, @unchecked Sendable {
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

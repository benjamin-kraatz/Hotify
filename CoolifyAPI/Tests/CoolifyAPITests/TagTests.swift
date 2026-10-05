import Foundation
import XCTest

@testable import CoolifyAPI

final class TagTests: XCTestCase {
    func testListTagsDecodesUUIDAndName() async throws {
        let client = try makeTagClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/tags")
            let body = Data(
                #"[{"uuid":"tag-1","name":"prod"},{"uuid":7,"name":2}]"#.utf8
            )
            return (200, body, [:])
        }

        let tags = try await client.tags()
        XCTAssertEqual(tags.count, 2)
        XCTAssertEqual(tags[0].uuid, "tag-1")
        XCTAssertEqual(tags[0].name, "prod")
        XCTAssertEqual(tags[1].uuid, "7")
        XCTAssertEqual(tags[1].name, "2")
    }

    func testCreateTagBodyIsTheName() async throws {
        let client = try makeTagClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/tags")
            let object = try XCTUnwrap(tagJSONObject(request))
            XCTAssertEqual(object["name"] as? String, "prod")
            XCTAssertEqual(object.count, 1)
            return (201, Data(#"{"uuid":"tag-1","name":"prod","created_at":"2026-01-01T00:00:00Z"}"#.utf8), [:])
        }

        let created = try await client.createTag(name: "prod")
        XCTAssertEqual(created.tag.uuid, "tag-1")
        XCTAssertEqual(created.tag.name, "prod")
        XCTAssertFalse(created.isAttachedToResource)
        XCTAssertTrue(created.resourceTags.isEmpty)
    }

    func testAddApplicationTagSendsTagNameOnEncodedPath() async throws {
        let client = try makeTagClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(
                request.url?.path(percentEncoded: true),
                "/api/v1/applications/app%2F1/tags"
            )
            let object = try XCTUnwrap(tagJSONObject(request))
            XCTAssertEqual(object["tag_name"] as? String, "prod")
            XCTAssertNil(object["tag_names"])
            XCTAssertEqual(object.count, 1)
            return (201, Data(#"[{"uuid":"tag-1","name":"prod"}]"#.utf8), [:])
        }

        let tags = try await client.addTag("prod", to: .application("app/1"))
        XCTAssertEqual(tags.map(\.name), ["prod"])
        XCTAssertEqual(tags.map(\.uuid), ["tag-1"])
    }

    func testDeleteDatabaseTagMethodAndPath() async throws {
        let client = try makeTagClient { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(
                request.url?.path(percentEncoded: true),
                "/api/v1/databases/db%2F2/tags/tag%2F9"
            )
            XCTAssertNil(tagRequestBody(request))
            return (200, Data(#"{"message":"Tag removed."}"#.utf8), [:])
        }

        try await client.removeTag("tag/9", from: .database("db/2"))
    }

    func testApplicationDecodesTagsAsNamesOrObjects() throws {
        let objects = try CoolifyJSON.decoder().decode(
            Application.self,
            from: Data(#"{"uuid":"app-1","name":"web","tags":[{"name":"prod"}]}"#.utf8)
        )
        XCTAssertEqual(objects.tags, ["prod"])

        let names = try CoolifyJSON.decoder().decode(
            Application.self,
            from: Data(#"{"uuid":"app-1","name":"web","tags":["prod"]}"#.utf8)
        )
        XCTAssertEqual(names.tags, ["prod"])

        let absent = try CoolifyJSON.decoder().decode(
            Application.self,
            from: Data(#"{"uuid":"app-1","name":"web"}"#.utf8)
        )
        XCTAssertEqual(absent.tags, [])
    }
}

private func tagRequestBody(_ request: URLRequest) -> String? {
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

private func tagJSONObject(_ request: URLRequest) -> [String: Any]? {
    guard let body = tagRequestBody(request), let data = body.data(using: .utf8) else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

private func makeTagClient(
    responder: @escaping @Sendable (URLRequest) throws -> (Int, Data, [String: String])
) throws -> CoolifyClient {
    TagURLProtocol.responder = responder
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [TagURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return try CoolifyClient(instanceURL: "http://coolify.example:8000", token: "test-token", session: session)
}

private final class TagURLProtocol: URLProtocol, @unchecked Sendable {
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

import Foundation
import XCTest

@testable import CoolifyAPI

final class SharedVariableScopeTests: XCTestCase {
    func testTeamRequests() async throws {
        let client = try makeScopeClient { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/v1/team/envs"):
                XCTAssertNil(bodyText(request))
                return (
                    200,
                    Data(
                        """
                        [{"id":7,"key":"API_URL","value":"https://api.example.com","is_literal":1,
                          "is_multiline":0,"is_shown_once":0},
                         {"id":8,"key":"HIDDEN"}]
                        """.utf8
                    ),
                    [:]
                )
            case ("POST", "/api/v1/team/envs"):
                let body = jsonBody(request)
                XCTAssertEqual(
                    body,
                    [
                        "is_literal": true,
                        "is_multiline": false,
                        "is_shown_once": false,
                        "key": "API_URL",
                        "value": "https://api.example.com",
                    ] as NSDictionary?
                )
                XCTAssertNil(body?["comment"])
                return (201, Data(#"{"id":15}"#.utf8), [:])
            case ("PATCH", "/api/v1/team/envs/13"):
                let body = jsonBody(request)
                XCTAssertEqual(body?["key"] as? String, "API_URL")
                XCTAssertNil(body?["comment"])
                return (200, Data(#"{"id":13,"key":"API_URL","is_literal":1}"#.utf8), [:])
            case ("DELETE", "/api/v1/team/envs/13"):
                XCTAssertNil(bodyText(request))
                return (200, Data(#"{"message":"Environment variable deleted."}"#.utf8), [:])
            default:
                XCTFail("Unexpected \(request.httpMethod ?? "") \(request.url?.path ?? "")")
                return (404, Data(), [:])
            }
        }

        let listed = try await client.sharedVariables(in: .team)
        XCTAssertEqual(listed.map(\.id), [7, 8])
        XCTAssertTrue(listed[0].isLiteral)
        XCTAssertEqual(listed[0].value, "https://api.example.com")
        // A token without read:sensitive omits value. That is not an empty value.
        XCTAssertNil(listed[1].value)

        let created = try await client.createSharedVariable(
            SharedVariableDraft(key: "API_URL", value: "https://api.example.com", isLiteral: true),
            in: .team
        )
        XCTAssertEqual(created, 15)

        let updated = try await client.updateSharedVariable(
            13,
            with: SharedVariableDraft(key: "API_URL", value: "https://api.example.com", isLiteral: true),
            in: .team
        )
        XCTAssertEqual(updated.id, 13)
        XCTAssertTrue(updated.isLiteral)

        try await client.deleteSharedVariable(13, from: .team)
    }

    func testServerRequests() async throws {
        let client = try makeScopeClient { request in
            let path = request.url?.path
            switch (request.httpMethod, path) {
            case ("GET", "/api/v1/servers/server-1/envs"):
                return (200, Data(#"[{"id":4,"key":"REGION","is_literal":1}]"#.utf8), [:])
            case ("POST", "/api/v1/servers/server-1/envs"):
                let body = jsonBody(request)
                XCTAssertEqual(
                    body,
                    [
                        "is_literal": false,
                        "is_multiline": false,
                        "is_shown_once": false,
                        "key": "REGION",
                        "value": "eu",
                    ] as NSDictionary?
                )
                XCTAssertNil(body?["comment"])
                return (201, Data(#"{"id":9}"#.utf8), [:])
            case ("PATCH", "/api/v1/servers/server-1/envs/9"):
                XCTAssertNil(jsonBody(request)?["comment"])
                return (200, Data(#"{"id":9,"key":"REGION","is_literal":1}"#.utf8), [:])
            case ("DELETE", "/api/v1/servers/server-1/envs/9"):
                return (200, Data(#"{"message":"Environment variable deleted."}"#.utf8), [:])
            default:
                XCTFail("Unexpected \(request.httpMethod ?? "") \(path ?? "")")
                return (404, Data(), [:])
            }
        }

        let scope = SharedVariableScope.server("server-1")
        let listed = try await client.sharedVariables(in: scope)
        XCTAssertEqual(listed.map(\.id), [4])
        XCTAssertTrue(listed[0].isLiteral)

        let created = try await client.createSharedVariable(
            SharedVariableDraft(key: "REGION", value: "eu"),
            in: scope
        )
        XCTAssertEqual(created, 9)
        let updated = try await client.updateSharedVariable(
            9,
            with: SharedVariableDraft(key: "REGION", value: "eu"),
            in: scope
        )
        XCTAssertTrue(updated.isLiteral)
        try await client.deleteSharedVariable(9, from: scope)
    }

    func testDuplicateKeyIsANormalError() async throws {
        let client = try makeScopeClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/team/envs")
            return (409, Data(#"{"message":"Environment variable already exists."}"#.utf8), [:])
        }
        do {
            _ = try await client.createSharedVariable(
                SharedVariableDraft(key: "API_URL", value: "https://api.example.com"),
                in: .team
            )
            XCTFail("A duplicate key should fail.")
        } catch let error as CoolifyError {
            XCTAssertEqual(error.statusCode, 409)
            XCTAssertEqual(error.message, "Environment variable already exists.")
        }
    }

    func testPathsEncodeTheScope() {
        XCTAssertEqual(SharedVariableScope.team.path, "team/envs")
        XCTAssertEqual(SharedVariableScope.server("server-1").path, "servers/server-1/envs")
        XCTAssertEqual(SharedVariableScope.server("build/1").path, "servers/build%2F1/envs")
    }

    func testLiteralDecodesFromOne() throws {
        let variable = try CoolifyJSON.decoder().decode(
            SharedVariable.self,
            from: Data(#"{"id":4,"key":"API_URL","value":"https://api.example.com","is_literal":1}"#.utf8)
        )
        XCTAssertEqual(variable.id, 4)
        XCTAssertTrue(variable.isLiteral)
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

private func makeScopeClient(
    responder: @escaping @Sendable (URLRequest) throws -> (Int, Data, [String: String])
) throws -> CoolifyClient {
    SharedVariableScopeURLProtocol.responder = responder
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SharedVariableScopeURLProtocol.self]
    return try CoolifyClient(
        instanceURL: "http://coolify.example:8000",
        token: "test-token",
        session: URLSession(configuration: configuration)
    )
}

private final class SharedVariableScopeURLProtocol: URLProtocol, @unchecked Sendable {
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

import Foundation
import XCTest

@testable import CoolifyAPI

final class CloudflareTunnelTests: XCTestCase {
    func testGetDecodesBooleanDigit() async throws {
        let client = try makeTunnelClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/servers/server-1/cloudflare-tunnel")
            return (
                200,
                Data(#"{"ip":"10.0.0.8","ip_previous":"203.0.113.4","is_cloudflare_tunnel":1}"#.utf8),
                [:]
            )
        }
        let tunnel = try await client.cloudflareTunnel(uuid: "server-1")
        XCTAssertEqual(tunnel.isCloudflareTunnel, true)
        XCTAssertEqual(tunnel.ip, "10.0.0.8")
        XCTAssertEqual(tunnel.ipPrevious, "203.0.113.4")
    }

    func testUpdateSendsOnlyTheFlag() async throws {
        let client = try makeTunnelClient { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/servers/server-1/cloudflare-tunnel")
            XCTAssertEqual(jsonBody(request), ["is_cloudflare_tunnel": true] as NSDictionary?)
            return (
                200,
                Data(#"{"ip":"10.0.0.8","ip_previous":null,"is_cloudflare_tunnel":1}"#.utf8),
                [:]
            )
        }
        let updated = try await client.updateCloudflareTunnel(uuid: "server-1", isCloudflareTunnel: true)
        XCTAssertEqual(updated.isCloudflareTunnel, true)
        XCTAssertNil(updated.ipPrevious)
    }

    func testEnablePosts() async throws {
        let client = try makeTunnelClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/servers/server-1/cloudflare-tunnel/enable")
            XCTAssertNil(bodyText(request))
            return (
                200,
                Data(
                    """
                    {"message":"Cloudflare Tunnel enabled.","ip":"10.0.0.8",
                     "ip_previous":"203.0.113.4","is_cloudflare_tunnel":1}
                    """.utf8
                ),
                [:]
            )
        }
        let tunnel = try await client.enableCloudflareTunnel(uuid: "server-1")
        XCTAssertEqual(tunnel.isCloudflareTunnel, true)
    }

    func testDisablePosts() async throws {
        let client = try makeTunnelClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/servers/server-1/cloudflare-tunnel/disable")
            XCTAssertNil(bodyText(request))
            return (
                200,
                Data(
                    """
                    {"message":"Cloudflare Tunnel disabled.","ip":"203.0.113.4",
                     "ip_previous":"203.0.113.4","is_cloudflare_tunnel":0}
                    """.utf8
                ),
                [:]
            )
        }
        let tunnel = try await client.disableCloudflareTunnel(uuid: "server-1")
        XCTAssertEqual(tunnel.isCloudflareTunnel, false)
        XCTAssertEqual(tunnel.ip, "203.0.113.4")
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

private func makeTunnelClient(
    responder: @escaping @Sendable (URLRequest) throws -> (Int, Data, [String: String])
) throws -> CoolifyClient {
    CloudflareTunnelURLProtocol.responder = responder
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CloudflareTunnelURLProtocol.self]
    return try CoolifyClient(
        instanceURL: "http://coolify.example:8000",
        token: "test-token",
        session: URLSession(configuration: configuration)
    )
}

private final class CloudflareTunnelURLProtocol: URLProtocol, @unchecked Sendable {
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

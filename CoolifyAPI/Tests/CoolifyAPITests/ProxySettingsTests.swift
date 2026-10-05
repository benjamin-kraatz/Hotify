import Foundation
import XCTest

@testable import CoolifyAPI

final class ProxySettingsTests: XCTestCase {
    func testUpdateProxySendsRedirectAndOmitsConfiguration() async throws {
        let client = try makeProxyClient { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/servers/server-1/proxy")
            XCTAssertEqual(
                jsonObject(request),
                [
                    "redirect_enabled": true,
                    "redirect_url": "https://example.com",
                    "generate_exact_labels": false,
                    "proxy_type": "traefik",
                ] as NSDictionary?
            )
            XCTAssertFalse(jsonKeys(request).contains("configuration"))
            return (200, Data(#"{"proxy_type":"traefik","status":"running","redirect_enabled":1}"#.utf8), [:])
        }
        let proxy = try await client.updateServerProxy(
            uuid: "server-1",
            redirectEnabled: true,
            redirectURL: "https://example.com",
            generateExactLabels: false,
            proxyType: "traefik"
        )
        XCTAssertEqual(proxy.proxyType, "traefik")
        XCTAssertEqual(proxy.redirectEnabled, true)
    }

    func testUpdateProxyOmitsNilRedirect() async throws {
        let client = try makeProxyClient { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(
                request.url?.absoluteString,
                "http://coolify.example:8000/api/v1/servers/srv%2F1/proxy"
            )
            XCTAssertEqual(jsonObject(request), ["redirect_enabled": false, "proxy_type": "caddy"] as NSDictionary?)
            XCTAssertFalse(jsonKeys(request).contains("redirect_url"))
            XCTAssertFalse(jsonKeys(request).contains("configuration"))
            return (200, Data(#"{"proxy_type":"caddy","redirect_enabled":0}"#.utf8), [:])
        }
        _ = try await client.updateServerProxy(
            uuid: "srv/1",
            redirectEnabled: false,
            redirectURL: nil,
            proxyType: "caddy"
        )
    }

    func testUpdateProxyClearsRedirectWithNull() async throws {
        let client = try makeProxyClient { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(
                jsonObject(request),
                ["redirect_enabled": true, "redirect_url": NSNull()] as NSDictionary?
            )
            XCTAssertFalse(jsonKeys(request).contains("configuration"))
            return (200, Data(#"{"redirect_enabled":1,"redirect_url":null}"#.utf8), [:])
        }
        let proxy = try await client.updateServerProxy(
            uuid: "server-1",
            redirectEnabled: true,
            clearRedirectURL: true
        )
        XCTAssertNil(proxy.redirectUrl)
        XCTAssertEqual(proxy.redirectEnabled, true)
    }

    func testSaveProxyConfigurationPutsBase64() async throws {
        let yaml = "services:\n  proxy:\n    image: example\n"
        let encoded = Data(yaml.utf8).base64EncodedString()
        let client = try makeProxyClient { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.path, "/api/v1/servers/server-1/proxy/configuration")
            let configuration = jsonObject(request)?["configuration"] as? String
            XCTAssertEqual(jsonKeys(request), Set(["configuration"]))
            XCTAssertEqual(configuration, encoded)
            XCTAssertNotEqual(configuration, yaml)
            XCTAssertFalse(configuration?.contains("image: example") ?? true)
            return (200, Data(#"{"message":"Proxy configuration saved.","proxy_type":"traefik"}"#.utf8), [:])
        }
        let proxy = try await client.saveServerProxyConfiguration(uuid: "server-1", configuration: yaml)
        XCTAssertEqual(proxy.proxyType, "traefik")
    }

    func testProxyReadingReturnsConfigurationOnlyWhenPresent() async throws {
        let yaml = "services:\n  proxy:\n    image: example\n"
        let withFile = try JSONSerialization.data(withJSONObject: [
            "proxy_type": "traefik",
            "status": "running",
            "redirect_enabled": 1,
            "redirect_url": "https://example.com",
            "configuration": yaml,
        ])
        let present = try makeProxyClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/servers/server-1/proxy")
            return (200, withFile, [:])
        }
        let reading = try await present.serverProxyReading(uuid: "server-1")
        XCTAssertEqual(reading.configuration, yaml)
        XCTAssertEqual(reading.proxy.proxyType, "traefik")
        XCTAssertEqual(reading.proxy.redirectUrl, "https://example.com")

        let omitted = try makeProxyClient { _ in
            (200, Data(#"{"proxy_type":"nginx","status":"running","redirect_enabled":0}"#.utf8), [:])
        }
        let missing = try await omitted.serverProxyReading(uuid: "server-1")
        XCTAssertNil(missing.configuration)
        XCTAssertEqual(missing.proxy.proxyType, "nginx")

        let nullFile = try JSONSerialization.data(withJSONObject: [
            "proxy_type": "caddy",
            "configuration": NSNull(),
        ])
        let nulled = try makeProxyClient { _ in
            (200, nullFile, [:])
        }
        let empty = try await nulled.serverProxyReading(uuid: "server-1")
        XCTAssertNil(empty.configuration)
        XCTAssertEqual(empty.proxy.proxyType, "caddy")
    }
}

private func bodyData(_ request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
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
    return data
}

private func jsonObject(_ request: URLRequest) -> NSDictionary? {
    guard let data = bodyData(request) else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? NSDictionary
}

private func jsonKeys(_ request: URLRequest) -> Set<String> {
    Set((jsonObject(request)?.allKeys as? [String]) ?? [])
}

private func makeProxyClient(
    responder: @escaping @Sendable (URLRequest) throws -> (Int, Data, [String: String])
) throws -> CoolifyClient {
    ProxySettingsURLProtocol.responder = responder
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ProxySettingsURLProtocol.self]
    return try CoolifyClient(
        instanceURL: "http://coolify.example:8000",
        token: "test-token",
        session: URLSession(configuration: configuration)
    )
}

private final class ProxySettingsURLProtocol: URLProtocol, @unchecked Sendable {
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

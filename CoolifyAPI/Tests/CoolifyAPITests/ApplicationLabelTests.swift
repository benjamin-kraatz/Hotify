import Foundation
import XCTest

@testable import CoolifyAPI

final class ApplicationLabelTests: XCTestCase {
    func testPatchBodyIncludesLabelsWhenSetAndOmitsThemWhenNil() async throws {
        let set = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/applications/app-1")
            XCTAssertEqual(
                jsonBody(request),
                [
                    "custom_labels": Data(
                        "traefik.enable=true\ntraefik.http.routers.app.rule=Host(`app.example.com`)".utf8
                    ).base64EncodedString(),
                    "is_container_label_escape_enabled": false,
                ] as NSDictionary)
            return (200, Data(#"{"uuid":"app-1"}"#.utf8), [:])
        }
        try await set.updateApplication(
            "app-1",
            ApplicationUpdate(
                customLabels: "traefik.enable=true\ntraefik.http.routers.app.rule=Host(`app.example.com`)",
                isContainerLabelEscapeEnabled: false))

        let cleared = try makeClient { request in
            XCTAssertEqual(
                jsonBody(request),
                [
                    "custom_labels": "",
                    "is_container_label_escape_enabled": true,
                ] as NSDictionary)
            return (200, Data(#"{"uuid":"app-1"}"#.utf8), [:])
        }
        try await cleared.updateApplication(
            "app-1", ApplicationUpdate(customLabels: "", isContainerLabelEscapeEnabled: true))

        let omitted = try makeClient { request in
            let body = jsonBody(request)
            XCTAssertNil(body?["custom_labels"])
            XCTAssertNil(body?["is_container_label_escape_enabled"])
            XCTAssertEqual(body, ["name": "site"] as NSDictionary)
            return (200, Data(#"{"uuid":"app-1"}"#.utf8), [:])
        }
        try await omitted.updateApplication("app-1", ApplicationUpdate(name: "site"))

        let empty = try CoolifyJSON.encoder().encode(ApplicationUpdate())
        let object = try JSONSerialization.jsonObject(with: empty) as? NSDictionary
        XCTAssertNil(object?["custom_labels"])
        XCTAssertNil(object?["is_container_label_escape_enabled"])
        XCTAssertEqual(object, [:] as NSDictionary)
    }

    func testApplicationDecodesAnEscapeFlagOfZero() throws {
        let present = #"""
            {"uuid":"app","name":"site","custom_labels":"traefik.enable=true","is_container_label_escape_enabled":0}
            """#
        let application = try CoolifyJSON.decoder().decode(Application.self, from: Data(present.utf8))
        XCTAssertEqual(application.customLabels, "traefik.enable=true")
        XCTAssertEqual(application.isContainerLabelEscapeEnabled, false)

        let missing = #"""
            {"uuid":"bare","name":"bare"}
            """#
        let bare = try CoolifyJSON.decoder().decode(Application.self, from: Data(missing.utf8))
        XCTAssertNil(bare.customLabels)
        XCTAssertNil(bare.isContainerLabelEscapeEnabled)
    }

    func testApplicationDecodesBase64Labels() throws {
        let labels = "traefik.enable=true\ntraefik.http.routers.app.rule=Host(`app.example.com`)"
        let json = #"{"uuid":"app","name":"site","custom_labels":"\#(Data(labels.utf8).base64EncodedString())"}"#
        let application = try CoolifyJSON.decoder().decode(Application.self, from: Data(json.utf8))
        XCTAssertEqual(application.customLabels, labels)
    }
}

private func jsonBody(_ request: URLRequest) -> NSDictionary? {
    guard let text = bodyText(request) else { return nil }
    return try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? NSDictionary
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

private func makeClient(
    instanceURL: String = "http://coolify.example:8000",
    responder: @escaping @Sendable (URLRequest) throws -> (Int, Data, [String: String])
) throws -> CoolifyClient {
    ApplicationLabelURLProtocol.responder = responder
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ApplicationLabelURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return try CoolifyClient(instanceURL: instanceURL, token: "test-token", session: session)
}

private final class ApplicationLabelURLProtocol: URLProtocol, @unchecked Sendable {
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

import Foundation
import XCTest

@testable import CoolifyAPI

final class ResourceLimitsTests: XCTestCase {
    func testPatchSendsOnlyTheLimitsThatAreSet() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/applications/app-1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(
                jsonBody(request),
                ["limits_cpus": "1.5", "limits_memory": "512m"] as NSDictionary)
            return (200, Data(#"{"uuid":"app-1"}"#.utf8), [:])
        }
        try await client.updateApplication(
            "app-1", ApplicationUpdate(limits: ResourceLimits(cpus: "1.5", memory: "512m")))
    }

    func testPatchLiftsLimitsWithZeroNotAnEmptyString() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(
                jsonBody(request),
                ["limits_cpus": "0", "limits_memory": "0", "limits_memory_swap": "0"] as NSDictionary)
            return (200, Data(#"{"uuid":"app-1"}"#.utf8), [:])
        }
        try await client.updateApplication(
            "app-1",
            ApplicationUpdate(
                limits: ResourceLimits(
                    cpus: ResourceLimits.none, memory: ResourceLimits.none, memorySwap: ResourceLimits.none)))
    }

    func testLimitsSitFlatBesideOtherFieldsAndStayOutWhenNil() async throws {
        let combined = try makeClient { request in
            XCTAssertEqual(
                jsonBody(request),
                [
                    "name": "site",
                    "health_check_enabled": true,
                    "health_check_interval": 30,
                    "limits_memory": "1g",
                ] as NSDictionary)
            return (200, Data(#"{"uuid":"app-1"}"#.utf8), [:])
        }
        try await combined.updateApplication(
            "app-1",
            ApplicationUpdate(
                name: "site",
                healthCheck: HealthCheck(isEnabled: true, interval: 30),
                limits: ResourceLimits(memory: "1g")))

        let omitted = try makeClient { request in
            let body = jsonBody(request)
            XCTAssertEqual(body, ["name": "site"] as NSDictionary)
            XCTAssertFalse(body?.allKeys.contains { "\($0)".hasPrefix("limits_") } ?? true)
            return (200, Data(#"{"uuid":"app-1"}"#.utf8), [:])
        }
        try await omitted.updateApplication("app-1", ApplicationUpdate(name: "site"))
    }

    func testLimitsCountAsAChangeThatNeedsARedeploy() {
        let update = ApplicationUpdate(limits: ResourceLimits(cpus: "2"))
        XCTAssertFalse(update.isEmpty)
        XCTAssertTrue(update.needsRedeploy)
        XCTAssertFalse(ApplicationUpdate(name: "site").needsRedeploy)
        XCTAssertTrue(ResourceLimits().isEmpty)
    }

    func testApplicationDecodesLimitsOfMixedShapes() throws {
        // `limits_cpus` is a string column, but a number is what a hand-edited row or an older instance may send.
        let json = #"""
            {"uuid":"app","name":"site","limits_cpus":0.5,"limits_memory":"512m","limits_memory_swap":"0",
             "limits_memory_reservation":"256M","limits_memory_swappiness":60,"limits_cpuset":null,
             "limits_cpu_shares":1024}
            """#
        let application = try CoolifyJSON.decoder().decode(Application.self, from: Data(json.utf8))
        XCTAssertEqual(
            application.limits,
            ResourceLimits(cpus: "0.5", memory: "512m", memorySwap: "0", memoryReservation: "256M"))

        let whole = #"{"uuid":"app","name":"site","limits_cpus":2}"#
        XCTAssertEqual(
            try CoolifyJSON.decoder().decode(Application.self, from: Data(whole.utf8)).limits?.cpus, "2")

        let bare = #"{"uuid":"bare","name":"bare"}"#
        let missing = try CoolifyJSON.decoder().decode(Application.self, from: Data(bare.utf8))
        XCTAssertEqual(missing.limits, ResourceLimits())
    }

    func testBytesReadDockerSizes() {
        XCTAssertEqual(ResourceLimits.bytes(in: "0"), 0)
        XCTAssertEqual(ResourceLimits.bytes(in: "512m"), 512 * 1_048_576)
        XCTAssertEqual(ResourceLimits.bytes(in: "1G"), 1_073_741_824)
        XCTAssertEqual(ResourceLimits.bytes(in: "64k"), 65_536)
        XCTAssertEqual(ResourceLimits.bytes(in: "100b"), 100)
        XCTAssertEqual(ResourceLimits.bytes(in: "2048"), 2_048)
        XCTAssertEqual(ResourceLimits.bytes(in: "512mb"), 512 * 1_048_576)
        XCTAssertEqual(ResourceLimits.bytes(in: " 1g "), 1_073_741_824)
        XCTAssertNil(ResourceLimits.bytes(in: nil))
        XCTAssertNil(ResourceLimits.bytes(in: ""))
        XCTAssertNil(ResourceLimits.bytes(in: "-1"))
        XCTAssertNil(ResourceLimits.bytes(in: "1.5g"))
        XCTAssertNil(ResourceLimits.bytes(in: "1t"))
        XCTAssertNil(ResourceLimits.bytes(in: "99999999999999g"))
    }

    func testCPUCountFollowsCoolifysRule() {
        XCTAssertEqual(ResourceLimits.cpuCount(in: "0"), 0)
        XCTAssertEqual(ResourceLimits.cpuCount(in: "0.5"), 0.5)
        XCTAssertEqual(ResourceLimits.cpuCount(in: ".25"), 0.25)
        XCTAssertEqual(ResourceLimits.cpuCount(in: "2"), 2)
        XCTAssertNil(ResourceLimits.cpuCount(in: nil))
        XCTAssertNil(ResourceLimits.cpuCount(in: ""))
        XCTAssertNil(ResourceLimits.cpuCount(in: "1."))
        XCTAssertNil(ResourceLimits.cpuCount(in: "1,5"))
        XCTAssertNil(ResourceLimits.cpuCount(in: "-1"))
        XCTAssertNil(ResourceLimits.cpuCount(in: "two"))
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
    ResourceLimitsURLProtocol.responder = responder
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ResourceLimitsURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return try CoolifyClient(instanceURL: instanceURL, token: "test-token", session: session)
}

private final class ResourceLimitsURLProtocol: URLProtocol, @unchecked Sendable {
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

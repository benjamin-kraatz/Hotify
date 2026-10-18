import Foundation
import XCTest

@testable import CoolifyAPI

final class ComposeServiceTests: XCTestCase {
    /// Quotes, `$$`, a block scalar, a comment, non-ASCII text, and a trailing newline: everything a lossy round trip
    /// would change.
    private let compose = """
        # Hand-written, four spaces in.
        services:
            web:
                image: "nginx:1.27"
                command: >
                    sh -c 'echo $$HOME && exec nginx -g "daemon off;"'
                environment:
                    - SERVICE_URL_WEB_80
                    - GREETING=${GREETING:-Grüß Gott}
                    - API_TOKEN=${API_TOKEN:?}
            cache:
                image: redis:7 # pinned

        """

    func testCustomComposeCreationSendsBase64AndNoType() async throws {
        let compose = compose
        let client = try makeComposeClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/services")
            XCTAssertNil(request.url?.query)
            let object = try composeBodyObject(request)
            // Coolify refuses `type` together with `docker_compose_raw`, and any key it does not expect.
            XCTAssertEqual(
                Set(object.keys),
                ["docker_compose_raw", "name", "server_uuid", "project_uuid", "environment_uuid", "instant_deploy"])
            let encoded = try XCTUnwrap(object["docker_compose_raw"] as? String)
            // Coolify checks `base64_encode(base64_decode(x)) === x`, so only canonical padded base64 passes.
            XCTAssertEqual(encoded, Data(compose.utf8).base64EncodedString())
            let decoded = try XCTUnwrap(Data(base64Encoded: encoded).flatMap { String(data: $0, encoding: .utf8) })
            XCTAssertEqual(decoded, compose)
            XCTAssertEqual(object["instant_deploy"] as? Bool, false)
            return (201, Data(#"{"uuid":"svc-9","domains":[]}"#.utf8), [:])
        }

        let created = try await client.createService(
            ServiceDraft(
                compose: compose, name: "edge", serverUUID: "srv-1", projectUUID: "proj-1", environmentUUID: "env-1")
        )
        XCTAssertEqual(created.uuid, "svc-9")
        XCTAssertEqual(created.domains, [])
    }

    func testTemplateCreationStillSendsTypeAlone() throws {
        let draft = ServiceDraft(
            type: "ghost", serverUUID: "srv-1", projectUUID: "proj-1", environmentUUID: "env-1",
            destinationUUID: "dest-2")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: CoolifyJSON.encoder().encode(draft)) as? [String: Any])
        XCTAssertEqual(
            Set(object.keys),
            ["type", "server_uuid", "project_uuid", "environment_uuid", "destination_uuid", "instant_deploy"])
        XCTAssertEqual(object["type"] as? String, "ghost")
    }

    func testComposeUpdateSendsOnlyTheFile() async throws {
        let compose = compose
        let client = try makeComposeClient { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            let url = try XCTUnwrap(request.url)
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            XCTAssertEqual(components?.percentEncodedPath, "/api/v1/services/svc%201")
            let object = try composeBodyObject(request)
            XCTAssertEqual(Set(object.keys), ["docker_compose_raw"])
            let encoded = try XCTUnwrap(object["docker_compose_raw"] as? String)
            XCTAssertEqual(Data(base64Encoded: encoded).flatMap { String(data: $0, encoding: .utf8) }, compose)
            return (200, Data(#"{"uuid":"svc 1","domains":["https://web.example.com"]}"#.utf8), [:])
        }

        let updated = try await client.updateService("svc 1", ServiceUpdate(dockerComposeRaw: compose))
        XCTAssertEqual(updated.domains, ["https://web.example.com"])
    }

    func testComposeUpdateCarriesNameAndDomainsAlong() throws {
        let update = ServiceUpdate(
            name: "edge", dockerComposeRaw: "services: {}", urls: [ServiceDomain(name: "web", url: "")])
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: CoolifyJSON.encoder().encode(update)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["name", "docker_compose_raw", "urls"])
        XCTAssertEqual(object["docker_compose_raw"] as? String, Data("services: {}".utf8).base64EncodedString())
        // An empty update must stay empty, which is how the Settings tab knows there is nothing to send.
        XCTAssertEqual(String(data: try CoolifyJSON.encoder().encode(ServiceUpdate()), encoding: .utf8), "{}")
    }

    func testServiceReadsPlainComposeAndToleratesItsAbsence() throws {
        let readable = """
            {"uuid":"svc-1","name":"edge","service_type":null,
             "docker_compose_raw":"services:\\n  web:\\n    image: nginx\\n",
             "docker_compose":"services:\\n  web-svc-1:\\n    image: nginx\\n    labels: []\\n",
             "applications":[{"id":3,"name":"web","fqdn":null}]}
            """
        let service = try CoolifyJSON.decoder().decode(Service.self, from: Data(readable.utf8))
        XCTAssertEqual(service.dockerComposeRaw, "services:\n  web:\n    image: nginx\n")

        // A token without `read:sensitive` gets the same payload with both compose fields left out.
        let hidden = #"{"uuid":"svc-1","name":"edge","applications":[]}"#
        XCTAssertNil(try CoolifyJSON.decoder().decode(Service.self, from: Data(hidden.utf8)).dockerComposeRaw)

        // A file that happens to be valid base64 stays as it was sent back.
        let base64Like = #"{"uuid":"svc-1","name":"edge","docker_compose_raw":"c2VydmljZXM6"}"#
        XCTAssertEqual(
            try CoolifyJSON.decoder().decode(Service.self, from: Data(base64Like.utf8)).dockerComposeRaw,
            "c2VydmljZXM6")
    }

    func testRefusedComposeKeepsCoolifysReason() async throws {
        let client = try makeComposeClient { _ in
            // Coolify sends the compose reason as one string, not a list.
            let body = #"""
                {"message":"Validation failed.","errors":{"docker_compose_raw":"Docker Compose file must contain a \"services\" section"}}
                """#
            return (422, Data(body.utf8), [:])
        }
        do {
            _ = try await client.updateService("svc-1", ServiceUpdate(dockerComposeRaw: "volumes: {}"))
            XCTFail("A refused compose file should throw")
        } catch let error as CoolifyError {
            XCTAssertTrue(error.isValidation)
            XCTAssertEqual(
                error.fieldErrors["docker_compose_raw"], [#"Docker Compose file must contain a "services" section"#])
        }
    }

    func testOutlineReadsHandWrittenIndentation() {
        let outline = ComposeOutline(compose)
        XCTAssertEqual(outline.containers.map(\.name), ["web", "cache"])
        XCTAssertEqual(outline.containers.map(\.image), ["nginx:1.27", "redis:7"])
        XCTAssertEqual(outline.variables.map(\.key), ["GREETING", "API_TOKEN"])
        XCTAssertEqual(outline.requiredKeys, ["API_TOKEN"])
    }

    func testOutlineReadsQuotedFlowAndCRLFContainers() {
        let outline = ComposeOutline(
            "services:\r\n  \"api\":\r\n    image: 'ghcr.io/acme/api:2'\r\n  worker: {image: busybox}\r\nvolumes:\r\n  data: {}\r\n"
        )
        XCTAssertEqual(outline.containers.map(\.name), ["api", "worker"])
        XCTAssertEqual(outline.containers.first?.image, "ghcr.io/acme/api:2")
        // A flow mapping keeps its image to itself. The outline only names the container.
        XCTAssertNil(outline.containers.last?.image)
    }

    func testOutlineIgnoresNestedImageKeys() {
        let outline = ComposeOutline(
            """
            services:
              app:
                build:
                  image: not-this
                image: this
            """)
        XCTAssertEqual(outline.containers.map(\.image), ["this"])
    }

    func testCheckBlocksOnlyAnEmptyFile() {
        XCTAssertTrue(ComposeCheck("").isBlocking)
        XCTAssertTrue(ComposeCheck(" \n\t\n").isBlocking)
        XCTAssertEqual(ComposeCheck(compose).findings, [])
        // JSON is YAML too, and this reader cannot see inside it. It must not be told off.
        XCTAssertEqual(ComposeCheck(#"{"services":{"web":{"image":"nginx"}}}"#).findings, [])
        XCTAssertEqual(ComposeCheck("\"services\":\n  web:\n    image: nginx\n").findings, [])
    }

    func testCheckAdvisesOnLikelyMistakes() {
        let missing = ComposeCheck("web:\n  image: nginx\n")
        XCTAssertFalse(missing.isBlocking)
        XCTAssertEqual(missing.findings.map(\.severity), [.advice])

        let tabbed = ComposeCheck("services:\n\tweb:\n    image: nginx\n")
        XCTAssertFalse(tabbed.isBlocking)
        XCTAssertEqual(tabbed.findings.first?.line, 2)

        let building = ComposeCheck("services:\n  web:\n    build: .\n")
        XCTAssertFalse(building.isBlocking)
        XCTAssertEqual(building.findings.first?.line, 3)
    }
}

/// URLSession hands a protocol the body as a stream, not as `httpBody`.
private func composeBodyObject(_ request: URLRequest) throws -> [String: Any] {
    var data = request.httpBody ?? Data()
    if data.isEmpty, let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
    }
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func makeComposeClient(
    responder: @escaping @Sendable (URLRequest) throws -> (Int, Data, [String: String])
) throws -> CoolifyClient {
    ComposeURLProtocol.responder = responder
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ComposeURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return try CoolifyClient(instanceURL: "http://coolify.example:8000", token: "test-token", session: session)
}

private final class ComposeURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responder: (@Sendable (URLRequest) throws -> (Int, Data, [String: String]))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let responder = Self.responder, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (status, data, headers) = try responder(request)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

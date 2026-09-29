import Foundation
import XCTest

@testable import CoolifyAPI

final class CoolifyAPITests: XCTestCase {
    func testVariableSyncPreservesScopesReferencesAndUnavailableValues() throws {
        let source = try CoolifyJSON.decoder().decode(
            [EnvironmentVariable].self,
            from: Data(
                #"[{"uuid":"1","key":"URL","value":"{{team.URL}}","is_preview":1,"is_runtime":0,"is_buildtime":1},{"uuid":"2","key":"HIDDEN","is_preview":1},{"uuid":"3","key":"PRODUCTION","value":"untouched"}]"#
                    .utf8))
        let destination = try CoolifyJSON.decoder().decode(
            [EnvironmentVariable].self,
            from: Data(
                #"[{"uuid":"4","key":"EXTRA","value":"keep"},{"uuid":"5","key":"PREVIEW","value":"keep","is_preview":1}]"#
                    .utf8))
        let plan = try VariableSyncPlan(
            source: source, destination: destination, sourcePreview: true, destinationPreview: false,
            destinationIsApplication: true)
        XCTAssertEqual(plan.changes.map(\.key), ["EXTRA", "HIDDEN", "URL"])
        XCTAssertEqual(plan.changes[0].kind, .destinationOnly)
        XCTAssertEqual(plan.changes[1].kind, .unavailable)
        XCTAssertNil(plan.changes[1].draft)
        XCTAssertEqual(plan.changes[2].draft?.value, "{{team.URL}}")
        XCTAssertEqual(plan.changes[2].draft?.isPreview, false)
        XCTAssertEqual(plan.changes[2].draft?.isRuntime, false)
        let database = try VariableSyncPlan(
            source: source, destination: [], sourcePreview: true, destinationPreview: false,
            destinationIsApplication: false)
        XCTAssertNil(database.changes.last?.draft?.isPreview)
        XCTAssertNil(database.changes.last?.draft?.isRuntime)
        XCTAssertThrowsError(
            try VariableSyncPlan(
                source: source + source, destination: [], sourcePreview: true, destinationPreview: false,
                destinationIsApplication: true))
    }

    func testVariableSyncAcrossTwoHostsSendsReviewedWritesOnly() async throws {
        let sourceJSON =
            #"[{"uuid":"a","key":"CREATE","value":"new","is_runtime":0,"is_buildtime":1},{"uuid":"b","key":"UPDATE","value":"changed"}]"#
        let destinationJSON =
            #"[{"uuid":"c","key":"UPDATE","value":"old"},{"uuid":"delete-id","key":"EXTRA","value":"old"}]"#
        let responder: @Sendable (URLRequest) throws -> (Int, Data, [String: String]) = { request in
            if request.httpMethod == "GET" {
                return (200, Data((request.url?.host == "source.example" ? sourceJSON : destinationJSON).utf8), [:])
            }
            XCTAssertEqual(request.url?.host, "destination.example")
            XCTAssertTrue(queryItems(request).isEmpty)
            if request.httpMethod == "DELETE" {
                XCTAssertEqual(request.url?.path, "/api/v1/applications/destination/envs/delete-id")
                return (200, Data(#"{"message":"deleted"}"#.utf8), [:])
            }
            XCTAssertEqual(request.url?.path, "/api/v1/applications/destination/envs")
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data((bodyText(request) ?? "").utf8)) as? [String: Any])
            if request.httpMethod == "POST" {
                XCTAssertEqual(body["key"] as? String, "CREATE")
                XCTAssertEqual(body["is_runtime"] as? Bool, false)
                XCTAssertEqual(body["is_buildtime"] as? Bool, true)
            } else {
                XCTAssertEqual(request.httpMethod, "PATCH")
                XCTAssertEqual(body["key"] as? String, "UPDATE")
                XCTAssertEqual(body["value"] as? String, "changed")
            }
            XCTAssertEqual(body["is_preview"] as? Bool, false)
            XCTAssertEqual(body["is_literal"] as? Bool, false)
            XCTAssertEqual(body["is_multiline"] as? Bool, false)
            XCTAssertEqual(body["is_shown_once"] as? Bool, false)
            return (201, Data(#"{"uuid":"saved"}"#.utf8), [:])
        }
        let sourceClient = try makeClient(instanceURL: "http://source.example", responder: responder)
        let destinationClient = try makeClient(instanceURL: "http://destination.example", responder: responder)
        let source = try await sourceClient.environmentVariables(of: .application("source"))
        let destination = try await destinationClient.environmentVariables(of: .application("destination"))
        let plan = try VariableSyncPlan(
            source: source, destination: destination, sourcePreview: false, destinationPreview: false,
            destinationIsApplication: true)
        let result = try await destinationClient.applyVariableSync(
            plan.changes, plan: plan, to: .application("destination"))
        XCTAssertEqual(result.appliedKeys, ["CREATE", "UPDATE", "EXTRA"])
        XCTAssertNil(result.failedKey)
    }

    func testVariableSyncStopsAfterPartialFailureAndRejectsStaleComparison() async throws {
        let source = try CoolifyJSON.decoder().decode(
            [EnvironmentVariable].self,
            from: Data(
                #"[{"uuid":"1","key":"A","value":"a"},{"uuid":"2","key":"B","value":"b"},{"uuid":"3","key":"C","value":"c"}]"#
                    .utf8))
        let plan = try VariableSyncPlan(
            source: source, destination: [], sourcePreview: false, destinationPreview: false,
            destinationIsApplication: false)
        let client = try makeClient { request in
            if request.httpMethod == "GET" { return (200, Data("[]".utf8), [:]) }
            let body = bodyText(request) ?? ""
            XCTAssertFalse(body.contains("\"key\":\"C\""))
            if body.contains("\"key\":\"B\"") { return (500, Data(#"{"message":"failed"}"#.utf8), [:]) }
            return (201, Data(#"{"uuid":"saved"}"#.utf8), [:])
        }
        let result = try await client.applyVariableSync(plan.changes, plan: plan, to: .database("db"))
        XCTAssertEqual(result.appliedKeys, ["A"])
        XCTAssertEqual(result.failedKey, "B")
        let staleClient = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            return (200, Data(#"[{"uuid":"new","key":"EXTRA","value":"external change"}]"#.utf8), [:])
        }
        do {
            _ = try await staleClient.applyVariableSync(plan.changes, plan: plan, to: .database("db"))
            XCTFail("A stale comparison must not write")
        } catch { XCTAssertTrue(error.localizedDescription.contains("changed")) }
    }

    func testBackupFixturesAndManualRequest() async throws {
        let fixture =
            #"[{"uuid":"schedule","enabled":"1","frequency":"daily","executions":[{"uuid":"execution","status":"failed","size":"42","message":"Storage unavailable"}]}]"#
        let client = try makeClient { request in
            if request.httpMethod == "GET" { return (200, Data(fixture.utf8), [:]) }
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/databases/database/backups/schedule")
            XCTAssertTrue(queryItems(request).isEmpty)
            let body = try JSONSerialization.jsonObject(with: Data((bodyText(request) ?? "").utf8)) as? NSDictionary
            XCTAssertEqual(body, ["backup_now": true] as NSDictionary)
            return (200, Data(#"{"message":"Database backup configuration updated"}"#.utf8), [:])
        }
        let backups = try await client.databaseBackups("database")
        XCTAssertTrue(backups[0].enabled)
        XCTAssertEqual(backups[0].executions[0].size, 42)
        XCTAssertEqual(backups[0].executions[0].message, "Storage unavailable")
        _ = try await client.backUpNow(database: "database", backup: "schedule")
    }

    func testDeploymentDetailAndHistoryRequests() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            if request.url?.path == "/api/v1/deployments/deploy-1" {
                return (200, Data(#"{"deployment_uuid":"deploy-1","logs":"building"}"#.utf8), [:])
            }
            XCTAssertEqual(request.url?.path, "/api/v1/deployments/applications/app-1")
            XCTAssertEqual(
                queryItems(request), [URLQueryItem(name: "skip", value: "0"), URLQueryItem(name: "take", value: "40")])
            return (200, Data(#"{"count":0,"deployments":[]}"#.utf8), [:])
        }
        let deployment = try await client.deployment("deploy-1")
        XCTAssertEqual(deployment.logs, "building")
        _ = try await client.applicationDeployments("app-1", take: 40)
    }

    func testDeploymentOutputAcceptsEncodedAndExpandedEntries() throws {
        let entries = #"[{"output":"building","timestamp":"2026-09-29T10:00:00Z"},{"output":42}]"#
        let expanded = try CoolifyJSON.decoder().decode(DeploymentOutput.self, from: Data(entries.utf8))
        let encoded = try CoolifyJSON.decoder().decode(DeploymentOutput.self, from: JSONEncoder().encode(entries))
        XCTAssertEqual(expanded.text, "2026-09-29T10:00:00Z building\n42")
        XCTAssertEqual(encoded.text, expanded.text)
        let plain = try CoolifyJSON.decoder().decode(DeploymentOutput.self, from: JSONEncoder().encode("plain output"))
        XCTAssertEqual(plain.text, "plain output")
        let hidden = try CoolifyJSON.decoder().decode(Deployment.self, from: Data(#"{"deployment_uuid":"d"}"#.utf8))
        XCTAssertNil(hidden.logs)
    }

    func testAPIBaseAcceptsInstanceRootAPIRootAndMCPURL() throws {
        let root = try CoolifyClient(instanceURL: "http://coolify.example:8000", token: "token")
        XCTAssertEqual(root.apiBaseURL.absoluteString, "http://coolify.example:8000/api/v1")

        let api = try CoolifyClient(instanceURL: "https://app.coolify.io/api/v1/", token: "token")
        XCTAssertEqual(api.apiBaseURL.absoluteString, "https://app.coolify.io/api/v1")

        let mcp = try CoolifyClient(instanceURL: "http://coolify.example:8000/mcp", token: "token")
        XCTAssertEqual(mcp.apiBaseURL.absoluteString, "http://coolify.example:8000/api/v1")
    }

    func testApplicationSettingsAcceptIntegerBooleans() throws {
        let json = """
            {
              "uuid": "app-1",
              "name": "Web",
              "status": "running:healthy",
              "git_repository": "git@github.com:example/web.git",
              "created_at": "2026-09-18T12:02:18.000000Z",
              "settings": { "is_preview_deployments_enabled": true, "is_force_https_enabled": 1 }
            }
            """.data(using: .utf8)!

        let application = try CoolifyJSON.decoder().decode(Application.self, from: json)
        XCTAssertEqual(application.settings?.isForceHTTPSEnabled, true)
        XCTAssertEqual(application.settings?.isPreviewDeploymentsEnabled, true)
        XCTAssertNotNil(application.createdAtDate)
    }

    func testDeploymentPageReadsStringPullRequestID() throws {
        let json = """
            {
              "count": 1,
              "deployments": [{
                "deployment_uuid": "dep-1",
                "pull_request_id": "18",
                "is_api": 1,
                "commit_message": "fix: login redirect",
                "created_at": "2026-09-18T12:02:18.000000Z",
                "updated_at": "2026-09-18T12:03:30.000000Z"
              }]
            }
            """.data(using: .utf8)!

        let page = try CoolifyJSON.decoder().decode(DeploymentPage.self, from: json)
        XCTAssertEqual(page.deployments[0].pullRequestID, 18)
        XCTAssertTrue(page.deployments[0].isPreview)
        XCTAssertEqual(page.deployments[0].isAPI, true)
        XCTAssertEqual(page.deployments[0].commitMessage, "fix: login redirect")
        // Without `finished_at`, the last update stands in for the end of the deployment.
        let started = try XCTUnwrap(page.deployments[0].createdAtDate)
        let finished = try XCTUnwrap(page.deployments[0].finishedAtDate)
        XCTAssertEqual(finished.timeIntervalSince(started), 72, accuracy: 0.5)
    }

    func testServiceDecodeKeepsNestedContainerStatus() throws {
        let json = """
            {
              "uuid": "svc-1",
              "name": "convex",
              "status": "running:healthy",
              "service_type": "convex",
              "server_status": true,
              "applications": [{
                "id": 7,
                "name": "dashboard",
                "human_name": "dashboard",
                "status": "running:healthy"
              }]
            }
            """.data(using: .utf8)!

        let service = try CoolifyJSON.decoder().decode(Service.self, from: json)
        XCTAssertEqual(service.applications?.first?.parsedStatus?.isRunning, true)
    }

    func testResourcesReadEnvironmentIDAsNumberOrString() throws {
        let application = try CoolifyJSON.decoder().decode(
            Application.self,
            from: Data(#"{"uuid":"app-1","name":"Web","environment_id":"3"}"#.utf8)
        )
        XCTAssertEqual(application.environmentID, 3)

        let database = try CoolifyJSON.decoder().decode(
            Database.self,
            from: Data(#"{"uuid":"db-1","database_type":"standalone-postgresql","environment_id":4}"#.utf8)
        )
        XCTAssertEqual(database.environmentID, 4)
        XCTAssertEqual(database.databaseType, "standalone-postgresql")

        let service = try CoolifyJSON.decoder().decode(
            Service.self,
            from: Data(#"{"uuid":"svc-1","name":"convex","environment_id":5}"#.utf8)
        )
        XCTAssertEqual(service.environmentID, 5)
    }

    func testServiceLogsNameTheSubService() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/services/svc-1/logs")
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertTrue(items.contains(URLQueryItem(name: "sub_service_name", value: "kibana")))
            XCTAssertTrue(items.contains(URLQueryItem(name: "lines", value: "500")))
            XCTAssertTrue(items.contains(URLQueryItem(name: "show_timestamps", value: "1")))
            return (200, Data(#"{"logs":"ready"}"#.utf8), [:])
        }

        let logs = try await client.serviceLogs(
            "svc-1",
            subServiceName: "kibana",
            window: .lines(500),
            showTimestamps: true
        )
        XCTAssertEqual(logs, "ready")
    }

    func testPreviewDeleteAndDeployUsePullRequestID() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            if request.httpMethod == "DELETE" {
                XCTAssertEqual(request.url?.path, "/api/v1/applications/app-1/previews/18")
                return (200, Data(#"{"message":"Preview deletion request queued."}"#.utf8), [:])
            }
            XCTAssertEqual(request.url?.path, "/api/v1/deploy")
            let query = request.url?.query ?? ""
            XCTAssertTrue(query.contains("uuid=app-1"))
            XCTAssertTrue(query.contains("pull_request_id=18"))
            let body = #"{"deployments":[{"message":"queued","resource_uuid":"app-1","deployment_uuid":"dep-2"}]}"#
            return (200, Data(body.utf8), [:])
        }

        let deleted = try await client.deletePreview(applicationUUID: "app-1", pullRequestID: 18)
        XCTAssertEqual(deleted.message, "Preview deletion request queued.")
        let started = try await client.startPreview(applicationUUID: "app-1", pullRequestID: 18)
        XCTAssertEqual(started.deployments.first?.deploymentUUID, "dep-2")
    }

    func testResourceListControls() async throws {
        let queued = Data(#"{"message":"queued"}"#.utf8)
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.httpBody)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            switch request.url?.path {
            case "/api/v1/applications/app-1/start":
                XCTAssertEqual(
                    queryItems(request),
                    [
                        URLQueryItem(name: "force", value: "0"),
                        URLQueryItem(name: "instant_deploy", value: "0"),
                    ]
                )
            case "/api/v1/applications/app-1/stop":
                XCTAssertEqual(queryItems(request), [URLQueryItem(name: "docker_cleanup", value: "0")])
            case "/api/v1/applications/app-1/restart":
                XCTAssertNil(request.url?.query)
            case "/api/v1/databases/db-1/start":
                XCTAssertNil(request.url?.query)
            case "/api/v1/databases/db-1/stop":
                XCTAssertEqual(queryItems(request), [URLQueryItem(name: "docker_cleanup", value: "0")])
            case "/api/v1/databases/db-1/restart":
                XCTAssertNil(request.url?.query)
            case "/api/v1/services/svc-1/start":
                XCTAssertNil(request.url?.query)
            case "/api/v1/services/svc-1/stop":
                XCTAssertEqual(queryItems(request), [URLQueryItem(name: "docker_cleanup", value: "0")])
            case "/api/v1/services/svc-1/restart":
                XCTAssertEqual(queryItems(request), [URLQueryItem(name: "latest", value: "0")])
            case "/api/v1/deployments/dep-1/cancel":
                XCTAssertNil(request.url?.query)
            default:
                XCTFail("Unexpected \(request.httpMethod ?? "") \(request.url?.path ?? "")")
            }
            return (200, queued, [:])
        }

        _ = try await client.startApplication("app-1")
        _ = try await client.stopApplication("app-1", dockerCleanup: false)
        _ = try await client.restartApplication("app-1")
        _ = try await client.startDatabase("db-1")
        _ = try await client.stopDatabase("db-1", dockerCleanup: false)
        _ = try await client.restartDatabase("db-1")
        _ = try await client.startService("svc-1")
        _ = try await client.stopService("svc-1", dockerCleanup: false)
        _ = try await client.restartService("svc-1")
        _ = try await client.cancelDeployment("dep-1")
    }

    func testRedeployQueuesTheApplication() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/deploy")
            XCTAssertEqual(
                queryItems(request),
                [URLQueryItem(name: "force", value: "0"), URLQueryItem(name: "uuid", value: "app-1")]
            )
            return (200, Data(#"{"deployments":[{"resource_uuid":"app-1","deployment_uuid":"dep-3"}]}"#.utf8), [:])
        }

        let result = try await client.deploy(uuid: "app-1")
        XCTAssertEqual(result.deployments.first?.deploymentUUID, "dep-3")
    }

    func testEnvironmentVariablesKeepHiddenValuesApartFromEmptyOnes() throws {
        let json = """
            [
              { "uuid": "env-1", "key": "DATABASE_URL", "value": "postgres://db", "real_value": "postgres://db",
                "is_preview": 0, "is_literal": "1", "is_multiline": false, "is_shown_once": 0,
                "is_runtime": 1, "is_buildtime": 0 },
              { "uuid": "env-2", "key": "EMPTY", "value": "", "is_preview": 1 },
              { "uuid": "env-3", "key": "STRIPE_KEY", "is_shown_once": true }
            ]
            """.data(using: .utf8)!

        let variables = try CoolifyJSON.decoder().decode([EnvironmentVariable].self, from: json)
        XCTAssertEqual(variables[0].value, "postgres://db")
        XCTAssertEqual(variables[0].isLiteral, true)
        XCTAssertEqual(variables[0].isBuildtime, false)
        XCTAssertEqual(variables[1].value, "")
        XCTAssertEqual(variables[1].isPreview, true)
        XCTAssertNil(variables[1].isRuntime)
        // Coolify leaves the value out, rather than sending an empty one, for a shown-once variable.
        XCTAssertNil(variables[2].value)
        XCTAssertTrue(variables[2].isShownOnce)
    }

    func testEnvironmentVariableWritesSendEveryFlag() async throws {
        let client = try makeClient { request in
            XCTAssertNil(request.url?.query)
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/v1/applications/app-1/envs"):
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
                XCTAssertEqual(
                    bodyText(request),
                    #"{"is_literal":true,"is_multiline":false,"is_preview":false,"is_shown_once":false,"key":"API_URL","value":"https:\/\/api.example.com"}"#
                )
                return (201, Data(#"{"uuid":"env-9"}"#.utf8), [:])
            case ("PATCH", "/api/v1/services/svc-1/envs"):
                // Services have no preview variables, so the flag stays out of the body.
                XCTAssertEqual(
                    bodyText(request),
                    #"{"is_literal":false,"is_multiline":true,"is_shown_once":true,"key":"CERT","value":"a\nb"}"#
                )
                return (201, Data(#"{"uuid":"env-2","key":"CERT","is_multiline":1,"is_shown_once":1}"#.utf8), [:])
            case ("DELETE", "/api/v1/databases/db-1/envs/env-3"):
                XCTAssertNil(bodyText(request))
                return (200, Data(#"{"message":"Environment variable deleted."}"#.utf8), [:])
            default:
                XCTFail("Unexpected \(request.httpMethod ?? "") \(request.url?.path ?? "")")
                return (404, Data(), [:])
            }
        }

        let created = try await client.createEnvironmentVariable(
            EnvironmentVariableDraft(
                key: "API_URL", value: "https://api.example.com", isPreview: false, isLiteral: true),
            on: .application("app-1")
        )
        XCTAssertEqual(created.uuid, "env-9")
        let updated = try await client.updateEnvironmentVariable(
            EnvironmentVariableDraft(key: "CERT", value: "a\nb", isMultiline: true, isShownOnce: true),
            on: .service("svc-1")
        )
        XCTAssertTrue(updated.isShownOnce)
        try await client.deleteEnvironmentVariable("env-3", from: .database("db-1"))
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

private func queryItems(_ request: URLRequest) -> [URLQueryItem] {
    guard let url = request.url else { return [] }
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
}

private func makeClient(
    instanceURL: String = "http://coolify.example:8000",
    responder: @escaping @Sendable (URLRequest) throws -> (Int, Data, [String: String])
) throws -> CoolifyClient {
    MockURLProtocol.responder = responder
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return try CoolifyClient(instanceURL: instanceURL, token: "test-token", session: session)
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
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

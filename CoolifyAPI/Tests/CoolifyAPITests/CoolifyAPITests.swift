import Foundation
import XCTest

@testable import CoolifyAPI

final class CoolifyAPITests: XCTestCase {
    func testPreviewDeploymentRejectsProductionAndHTTP200Failures() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/deploy")
            XCTAssertEqual(
                queryItems(request),
                [
                    URLQueryItem(name: "force", value: "0"),
                    URLQueryItem(name: "uuid", value: "app-1"),
                    URLQueryItem(name: "pull_request_id", value: "18"),
                ])
            XCTAssertNil(bodyText(request))
            return (
                200,
                Data(
                    #"{"deployments":[{"message":"Pull request 18 not found for this resource.","resource_uuid":"app-1"}]}"#
                        .utf8), [:]
            )
        }
        for number in [0, -1, 18] {
            do {
                _ = try await client.deployPreview(applicationUUID: "app-1", pullRequestID: number)
                XCTFail("Preview must not deploy production or report an unqueued deployment as success")
            } catch let error as CoolifyError {
                XCTAssertTrue(error.message.contains(number == 18 ? "not found" : "positive"))
            }
        }
        do {
            _ = try await client.deployPreview(applicationUUID: "", pullRequestID: 18)
            XCTFail("Empty UUID must not reach deploy")
        } catch {}
    }

    func testPreviewDeploymentRequiresMatchingResourceAndDeploymentID() async throws {
        for fixture in [
            #"{"deployments":[{"resource_uuid":"other","deployment_uuid":"queued"}]}"#,
            #"{"deployments":[{"resource_uuid":"app","deployment_uuid":""}]}"#,
            #"{"message":"Skipped","deployments":[]}"#,
        ] {
            let client = try makeClient { _ in (200, Data(fixture.utf8), [:]) }
            do {
                _ = try await client.deployPreview(applicationUUID: "app", pullRequestID: 42)
                XCTFail("Unacknowledged preview should fail")
            } catch {}
        }
    }

    func testGitHubRepositoryParsingRejectsUntrustedHostsAndPaths() throws {
        for value in [
            "owner/repo", "https://github.com/owner/repo.git", "git@github.com:owner/repo.git",
            "ssh://git@github.com/owner/repo.git",
        ] {
            XCTAssertEqual(try GitHubRepository(value).label, "owner/repo")
        }
        for value in [
            "https://evil.example/owner/repo", "https://github.com.evil.example/owner/repo",
            "https://github.com/owner/repo?token=x", "../repo", "owner/..", "owner/repo/issues", "owner/%2F",
            "owner//repo", "http://github.com/owner/repo",
        ] {
            XCTAssertThrowsError(try GitHubRepository(value), value)
        }
    }

    func testGitHubPRRequestIsSeparateAndPaginated() async throws {
        MockURLProtocol.responder = { request in
            XCTAssertEqual(request.url?.host, "api.github.com")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/repos/owner/repo/pulls")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer github-only")
            XCTAssertEqual(
                queryItems(request),
                [
                    URLQueryItem(name: "state", value: "open"),
                    URLQueryItem(name: "sort", value: "created"),
                    URLQueryItem(name: "direction", value: "desc"),
                    URLQueryItem(name: "per_page", value: "50"),
                    URLQueryItem(name: "page", value: "2"),
                ])
            XCTAssertNil(bodyText(request))
            return (
                200, Data(#"[{"number":18,"title":"New checkout","draft":true,"head":{"ref":"feat/checkout"}}]"#.utf8),
                [:]
            )
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = GitHubPullRequestClient(session: URLSession(configuration: configuration))
        let prs = try await client.pullRequests(
            repository: GitHubRepository("owner/repo"), token: "github-only", page: 2)
        XCTAssertEqual(prs.first?.number, 18)
        XCTAssertEqual(prs.first?.head.ref, "feat/checkout")
        XCTAssertEqual(prs.first?.draft, true)
    }

    func testGitHubRedirectPolicyKeepsCredentialsOnTrustedOrigin() {
        for value in [
            "https://api.github.com/repositories/42/pulls", "https://api.github.com:443/repos/new/repo/pulls",
        ] {
            XCTAssertTrue(GitHubRedirectPolicy.permits(URL(string: value)))
        }
        for value in [
            "http://api.github.com/repos/o/r/pulls", "https://api.github.com:8443/pulls", "https://evil.example/pulls",
            "https://api.github.com.evil.example/pulls", "https://user@api.github.com/pulls",
        ] {
            XCTAssertFalse(GitHubRedirectPolicy.permits(URL(string: value)))
        }
        XCTAssertFalse(GitHubRedirectPolicy.permits(nil))
    }

    func testGitHubPublicRequestAndSanitizedErrors() async throws {
        MockURLProtocol.responder = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (404, Data(#"{"message":"secret response not displayed"}"#.utf8), [:])
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = GitHubPullRequestClient(session: URLSession(configuration: configuration))
        do {
            _ = try await client.pullRequests(repository: GitHubRepository("owner/repo"))
            XCTFail("Private repository must require access")
        } catch let error as CoolifyError {
            XCTAssertEqual(error.statusCode, 404)
            XCTAssertTrue(error.message.contains("private repository"))
            XCTAssertFalse(error.message.contains("secret response"))
        }
    }

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

    func testPreviewURLFollowsCoolifyTemplate() throws {
        func application(fqdn: String?, template: String?) throws -> Application {
            var object: [String: Any] = ["uuid": "app-1", "name": "Web"]
            object["fqdn"] = fqdn
            object["preview_url_template"] = template
            return try CoolifyJSON.decoder().decode(
                Application.self, from: JSONSerialization.data(withJSONObject: object))
        }

        let standard = try application(
            fqdn: "https://web.example.com,https://www.example.com", template: "{{pr_id}}.{{domain}}")
        XCTAssertEqual(standard.previewURL(pullRequest: 42)?.absoluteString, "https://42.web.example.com")

        let ported = try application(fqdn: "http://web.example.com:8080", template: "pr-{{pr_id}}.{{domain}}")
        XCTAssertEqual(ported.previewURL(pullRequest: 7)?.absoluteString, "http://pr-7.web.example.com:8080")

        // Coolify fills `{{random}}` once on the server, so the address cannot be rebuilt here.
        XCTAssertNil(
            try application(fqdn: "https://web.example.com", template: "{{random}}.{{domain}}").previewURL(
                pullRequest: 1))
        XCTAssertNil(try application(fqdn: nil, template: "{{pr_id}}.{{domain}}").previewURL(pullRequest: 1))
        XCTAssertNil(try application(fqdn: "https://web.example.com", template: nil).previewURL(pullRequest: 1))
        XCTAssertNil(standard.previewURL(pullRequest: 0))
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

    func testRollbackSendsTheTagAndReturnsTheDeployment() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/applications/app%201/rollback")
            XCTAssertTrue(queryItems(request).isEmpty)
            let body = try JSONSerialization.jsonObject(with: Data((bodyText(request) ?? "").utf8)) as? NSDictionary
            XCTAssertEqual(body, ["commit": "5aa01e77c3d4e5f60718293a4b5c6d7e8f901234"] as NSDictionary)
            return (200, Data(#"{"message":"Rollback deployment queued.","deployment_uuid":"dep-9"}"#.utf8), [:])
        }
        let deployment = try await client.rollback("app 1", to: "5aa01e77c3d4e5f60718293a4b5c6d7e8f901234")
        XCTAssertEqual(deployment, "dep-9")
    }

    func testRollbackWithoutADeploymentFails() async throws {
        let client = try makeClient { _ in
            (200, Data(#"{"message":"Deployment already queued for this commit."}"#.utf8), [:])
        }
        do {
            _ = try await client.rollback("app", to: "latest")
            XCTFail("A rollback Coolify did not queue must not count as queued")
        } catch let error as CoolifyError {
            XCTAssertEqual(error.message, "Deployment already queued for this commit.")
        }
    }

    func testRollbackImagesHideHelpersAndReadDockerDates() async throws {
        let current = "5aa01e77c3d4e5f60718293a4b5c6d7e8f901234"
        let older = "1b2c3d4e5f60718293a4b5c6d7e8f9012345678a"
        let fixture = """
            {"current":"\(current)","images":[
              {"tag":"\(older)","created_at":"2026-09-28 09:00:40 +0200 CEST","is_current":0},
              {"tag":"\(current)-build","created_at":"2026-09-30 16:21:00 +0000 UTC","is_current":false},
              {"tag":"pr-7-9f2c1ab4","created_at":"2026-10-01 08:00:00 +0000 UTC","is_current":false},
              {"tag":"build","created_at":"2026-09-30 16:20:00 +0000 UTC","is_current":false},
              {"tag":"\(current)","created_at":"2026-09-30 16:21:30 +0000 UTC","is_current":"1"}
            ]}
            """
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/applications/app/rollback-images")
            return (200, Data(fixture.utf8), [:])
        }
        let images = try await client.rollbackImages("app")
        XCTAssertEqual(images.images.count, 5)
        XCTAssertEqual(images.targets.map(\.tag), [current, older])
        XCTAssertEqual(images.targets.map(\.isCurrent), [true, false])
        XCTAssertEqual(images.targets[0].shortTag, "5aa01e7")
        let date = try XCTUnwrap(images.targets[1].createdAtDate)
        // 09:00:40 at +0200 is 07:00:40 UTC.
        XCTAssertEqual(date.timeIntervalSince1970, 1_790_578_840, accuracy: 0.5)

        let empty = try CoolifyJSON.decoder().decode(
            RollbackImages.self, from: Data(#"{"current":null,"images":[]}"#.utf8))
        XCTAssertNil(empty.current)
        XCTAssertTrue(empty.targets.isEmpty)
    }

    func testRollbackImagesMatchDeploymentsByCommitPrefix() {
        let image = RollbackImage(tag: "5aa01e77c3d4e5f60718293a4b5c6d7e8f901234")
        XCTAssertTrue(image.matches(commit: "5aa01e77"))
        XCTAssertTrue(image.matches(commit: "5AA01E77C3D4E5F60718293A4B5C6D7E8F901234"))
        XCTAssertFalse(image.matches(commit: "5aa01e"))
        XCTAssertFalse(image.matches(commit: "HEAD"))
        XCTAssertFalse(image.matches(commit: nil))
        XCTAssertFalse(image.matches(commit: "1b2c3d4e"))

        let tagged = RollbackImage(tag: "1.4.2")
        XCTAssertFalse(tagged.isCommit)
        XCTAssertEqual(tagged.shortTag, "1.4.2")
        XCTAssertFalse(tagged.matches(commit: "1.4.2"))
    }

    func testDeploymentReadsTheRollbackFlag() throws {
        let page = try CoolifyJSON.decoder().decode(
            DeploymentPage.self,
            from: Data(
                #"{"count":2,"deployments":[{"deployment_uuid":"a","rollback":1},{"deployment_uuid":"b","rollback":false}]}"#
                    .utf8))
        XCTAssertEqual(page.deployments.map(\.rollback), [true, false])
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

    func testServiceCreationSendsOnlyKnownFieldsAndReadsConflicts() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/services")
            // Coolify 4.3 rejects unknown keys with 422, so a missing destination must leave the key out.
            XCTAssertEqual(
                bodyText(request),
                #"{"environment_uuid":"env-1","instant_deploy":false,"name":"blog","project_uuid":"proj-1","server_uuid":"srv-1","type":"ghost"}"#
            )
            let body = #"""
                {"message":"Domain conflicts detected. Use force_domain_override=true to proceed.",
                 "conflicts":[{"domain":"blog.example.com","resource_name":"marketing-site","resource_type":"application"}]}
                """#
            return (409, Data(body.utf8), [:])
        }
        do {
            _ = try await client.createService(
                ServiceDraft(
                    type: "ghost", name: "blog", serverUUID: "srv-1", projectUUID: "proj-1", environmentUUID: "env-1")
            )
            XCTFail("A conflict should throw")
        } catch let error as CoolifyError {
            XCTAssertEqual(error.statusCode, 409)
            XCTAssertEqual(
                error.conflicts,
                [
                    DomainConflict(
                        domain: "blog.example.com", resourceName: "marketing-site", resourceType: "application")
                ])
        }
    }

    func testProvisioningWritesShape() async throws {
        let client = try makeClient { request in
            let method = request.httpMethod ?? ""
            let path = request.url?.path ?? ""
            switch (method, path) {
            case ("PATCH", "/api/v1/services/svc-1"):
                XCTAssertEqual(
                    bodyText(request),
                    #"{"force_domain_override":true,"urls":[{"name":"ghost","url":"https:\/\/blog.example.com"}]}"#)
                return (200, Data(#"{"uuid":"svc-1","domains":["https://blog.example.com"]}"#.utf8), [:])
            case ("PATCH", "/api/v1/services/svc-1/envs/bulk"):
                XCTAssertEqual(bodyText(request), #"{"data":[{"key":"MAIL_HOST","value":"smtp.example.com"}]}"#)
                return (201, Data(#"[{"uuid":"env-1","key":"MAIL_HOST","value":"smtp.example.com"}]"#.utf8), [:])
            case ("DELETE", "/api/v1/services/svc-1"):
                XCTAssertEqual(
                    queryItems(request),
                    [
                        URLQueryItem(name: "delete_configurations", value: "true"),
                        URLQueryItem(name: "delete_volumes", value: "true"),
                        URLQueryItem(name: "docker_cleanup", value: "true"),
                        URLQueryItem(name: "delete_connected_networks", value: "true"),
                    ])
                return (200, Data(#"{"message":"Service deletion request queued."}"#.utf8), [:])
            case ("POST", "/api/v1/projects"):
                XCTAssertEqual(bodyText(request), #"{"name":"Website"}"#)
                return (201, Data(#"{"uuid":"proj-2"}"#.utf8), [:])
            case ("POST", "/api/v1/projects/proj-2/environments"):
                XCTAssertEqual(bodyText(request), #"{"name":"staging"}"#)
                return (201, Data(#"{"uuid":"env-2"}"#.utf8), [:])
            default:
                XCTFail("Unexpected \(method) \(path)")
                return (500, Data(), [:])
            }
        }

        let updated = try await client.updateService(
            "svc-1",
            ServiceUpdate(
                urls: [ServiceDomain(name: "ghost", url: "https://blog.example.com")], forceDomainOverride: true)
        )
        XCTAssertEqual(updated.domains, ["https://blog.example.com"])
        let saved = try await client.setEnvironmentVariables(
            [EnvironmentVariableValue(key: "MAIL_HOST", value: "smtp.example.com")], on: .service("svc-1"))
        XCTAssertEqual(saved.first?.key, "MAIL_HOST")
        try await client.deleteService("svc-1")
        let project = try await client.createProject(name: "Website")
        let environment = try await client.createEnvironment(name: "staging", inProject: project.uuid)
        XCTAssertEqual(environment.uuid, "env-2")
    }

    func testTemplateFeedKeepsSlugsAndOutlinesCompose() throws {
        let compose = """
            services:
              ghost:
                image: 'ghost:5'
                environment:
                  - SERVICE_URL_GHOST_2368
                  - 'database__connection__password=$SERVICE_PASSWORD_MYSQL'
                  - 'database__connection__database=${MYSQL_DATABASE-ghost}'
                  - 'mail__options__host=${MAIL_OPTIONS_HOST}'
                  - 'ADMIN_EMAIL=${ADMIN_EMAIL:?}'
              mysql:
                image: "mysql:8.0"
            volumes:
              ghost-content-data: {}
            """
        let feed = """
            {
              "denoKV": {"slogan": "Deno KV", "compose": "\(Data(compose.utf8).base64EncodedString())", "port": 4512,
                         "tags": ["database"], "logo": "svgs/deno.svg", "template_last_updated_at": "2026-02-03T22:32:03+01:00"},
              "sparse": {"tags": "not a list"},
              "odd": 7
            }
            """
        let templates = try ServiceTemplateFeed.templates(from: Data(feed.utf8))
        XCTAssertEqual(templates.map(\.slug), ["denoKV", "sparse"])
        let template = try XCTUnwrap(templates.first)
        XCTAssertEqual(template.port, "4512")
        XCTAssertNotNil(template.updatedAtDate)

        let outline = template.outline
        XCTAssertEqual(outline.containers.map(\.name), ["ghost", "mysql"])
        XCTAssertEqual(outline.containers.map(\.image), ["ghost:5", "mysql:8.0"])
        XCTAssertEqual(outline.variables.map(\.key), ["MYSQL_DATABASE", "MAIL_OPTIONS_HOST", "ADMIN_EMAIL"])
        XCTAssertEqual(outline.variables.first?.defaultValue, "ghost")
        XCTAssertEqual(outline.requiredKeys, ["ADMIN_EMAIL"])
    }

    func testProjectDetailCarriesEnvironmentsAndCreationDate() throws {
        let json = """
            {
              "id": 4, "uuid": "proj-1", "name": "Website", "description": null,
              "team_id": 0, "created_at": "2026-03-02T09:30:00.000000Z",
              "environments": [
                { "id": 7, "uuid": "env-prod", "name": "production", "project_id": 4, "description": null },
                { "id": 9, "uuid": "env-stage", "name": "staging", "description": "Release candidates" }
              ]
            }
            """.data(using: .utf8)!

        let project = try CoolifyJSON.decoder().decode(Project.self, from: json)
        XCTAssertNil(project.description)
        XCTAssertNotNil(project.createdAtDate)
        XCTAssertEqual(project.environments?.map(\.uuid), ["env-prod", "env-stage"])
        XCTAssertEqual(project.environments?.last?.description, "Release candidates")

        // The list endpoint selects four columns and nothing else.
        let listed = try CoolifyJSON.decoder().decode(
            Project.self, from: Data(#"{"id":4,"uuid":"proj-1","name":"Website","description":"Marketing"}"#.utf8))
        XCTAssertNil(listed.environments)
        XCTAssertNil(listed.createdAtDate)
    }

    func testProjectAndEnvironmentWritesSendOnlyAllowedFields() async throws {
        let client = try makeClient { request in
            XCTAssertNil(request.url?.query)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            switch (request.httpMethod, request.url?.path) {
            case ("PATCH", "/api/v1/projects/proj-1"):
                XCTAssertEqual(bodyText(request), #"{"description":"","name":"Website"}"#)
                // Coolify answers an update with 201 and a cut-down project.
                return (201, Data(#"{"uuid":"proj-1","name":"Website","description":null}"#.utf8), [:])
            case ("POST", "/api/v1/projects/proj-1/environments"):
                // A description here would be an extra field, which Coolify rejects with 422.
                XCTAssertEqual(bodyText(request), #"{"name":"staging"}"#)
                return (201, Data(#"{"uuid":"env-new"}"#.utf8), [:])
            case ("PATCH", "/api/v1/projects/proj-1/environments/env-stage"):
                XCTAssertEqual(bodyText(request), #"{"description":"Release candidates","name":"preprod"}"#)
                return (
                    200, Data(#"{"uuid":"env-stage","name":"preprod","description":"Release candidates"}"#.utf8), [:]
                )
            default:
                XCTFail("Unexpected \(request.httpMethod ?? "") \(request.url?.path ?? "")")
                return (404, Data(), [:])
            }
        }

        let project = try await client.updateProject("proj-1", name: "Website", description: "")
        XCTAssertEqual(project.name, "Website")
        XCTAssertNil(project.description)
        let created = try await client.createEnvironment(name: "staging", inProject: "proj-1")
        XCTAssertEqual(created.uuid, "env-new")
        let environment = try await client.updateEnvironment(
            "env-stage", inProject: "proj-1", name: "preprod", description: "Release candidates")
        XCTAssertEqual(environment.name, "preprod")
    }

    func testSharedVariablesReadNumericIDsAndWithheldValues() throws {
        let json = """
            [
              { "id": 12, "key": "API_URL", "value": "https://api.example.com", "is_literal": 1,
                "is_multiline": false, "is_shown_once": 0, "comment": "Used by web and worker", "type": "project" },
              { "id": "13", "key": "STRIPE_KEY", "is_shown_once": true },
              { "id": 14, "key": "EMPTY", "value": "" }
            ]
            """.data(using: .utf8)!

        let variables = try CoolifyJSON.decoder().decode([SharedVariable].self, from: json)
        XCTAssertEqual(variables.map(\.id), [12, 13, 14])
        XCTAssertEqual(variables[0].value, "https://api.example.com")
        XCTAssertTrue(variables[0].isLiteral)
        XCTAssertEqual(variables[0].comment, "Used by web and worker")
        // Withheld, which is not the same as empty.
        XCTAssertNil(variables[1].value)
        XCTAssertTrue(variables[1].isShownOnce)
        XCTAssertEqual(variables[2].value, "")
        XCTAssertThrowsError(
            try CoolifyJSON.decoder().decode(SharedVariable.self, from: Data(#"{"key":"NO_ID"}"#.utf8)))
    }

    func testSharedVariableRequestsAddressTheScopeAndTheNumericID() async throws {
        let client = try makeClient { request in
            XCTAssertNil(request.url?.query)
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/v1/projects/proj-1/envs"):
                XCTAssertNil(bodyText(request))
                return (200, Data(#"[{"id":12,"key":"API_URL"}]"#.utf8), [:])
            case ("GET", "/api/v1/projects/proj-1/environments/env-prod/envs"):
                return (200, Data("[]".utf8), [:])
            case ("POST", "/api/v1/projects/proj-1/envs"):
                // No `is_preview`, `is_runtime`, or `comment`: Coolify answers 422 to fields outside its list.
                XCTAssertEqual(
                    bodyText(request),
                    #"{"is_literal":true,"is_multiline":false,"is_shown_once":false,"key":"API_URL","value":"https:\/\/api.example.com"}"#
                )
                return (201, Data(#"{"id":15}"#.utf8), [:])
            case ("PATCH", "/api/v1/projects/proj-1/environments/env-prod/envs/13"):
                XCTAssertEqual(
                    bodyText(request),
                    #"{"comment":"Rotated","is_literal":false,"is_multiline":false,"is_shown_once":true,"key":"STRIPE_KEY","value":"sk_live"}"#
                )
                return (200, Data(#"{"id":13,"key":"STRIPE_KEY","is_shown_once":true}"#.utf8), [:])
            case ("DELETE", "/api/v1/projects/proj-1/envs/12"):
                XCTAssertNil(bodyText(request))
                return (200, Data(#"{"message":"Environment variable deleted."}"#.utf8), [:])
            default:
                XCTFail("Unexpected \(request.httpMethod ?? "") \(request.url?.path ?? "")")
                return (404, Data(), [:])
            }
        }

        let project = SharedVariableScope.project("proj-1")
        let environment = SharedVariableScope.environment(project: "proj-1", environment: "env-prod")
        let listed = try await client.sharedVariables(in: project)
        XCTAssertEqual(listed.map(\.id), [12])
        let empty = try await client.sharedVariables(in: environment)
        XCTAssertTrue(empty.isEmpty)
        let created = try await client.createSharedVariable(
            SharedVariableDraft(key: "API_URL", value: "https://api.example.com", isLiteral: true), in: project)
        XCTAssertEqual(created, 15)
        let updated = try await client.updateSharedVariable(
            13,
            with: SharedVariableDraft(key: "STRIPE_KEY", value: "sk_live", isShownOnce: true, comment: "Rotated"),
            in: environment
        )
        XCTAssertNil(updated.value)
        try await client.deleteSharedVariable(12, from: project)
    }

    func testSettingsDecodeMixedHealthCheckAndComposeDomains() throws {
        // Coolify sends the health check port as a string, the flags as 0 and 1, and the compose domains as a JSON
        // string whose service names must keep their underscores.
        let application = try CoolifyJSON.decoder().decode(
            Application.self,
            from: Data(
                #"""
                {"uuid":"app","name":"web","build_pack":"dockercompose","redirect":"non-www",
                 "docker_compose_domains":"{\"my_app\":{\"domain\":\"https://a.example.com\"},\"worker\":{\"domain\":\"\"}}",
                 "health_check_enabled":1,"health_check_type":"http","health_check_path":"/health",
                 "health_check_port":"8080","health_check_return_code":200,"health_check_interval":"30",
                 "health_check_timeout":5,"health_check_retries":3,"health_check_start_period":10}
                """#.utf8))
        XCTAssertTrue(application.isDockerCompose)
        XCTAssertEqual(application.redirect, .nonWWW)
        XCTAssertEqual(application.dockerComposeDomains, ["my_app": "https://a.example.com", "worker": ""])
        XCTAssertEqual(application.healthCheck?.isEnabled, true)
        XCTAssertEqual(application.healthCheck?.kind, .http)
        XCTAssertEqual(application.healthCheck?.port, 8080)
        XCTAssertEqual(application.healthCheck?.interval, 30)

        let database = try CoolifyJSON.decoder().decode(
            Database.self,
            from: Data(
                #"{"uuid":"db","is_public":0,"public_port":"5433","health_check_enabled":true,"health_check_retries":5}"#
                    .utf8))
        XCTAssertEqual(database.isPublic, false)
        XCTAssertEqual(database.publicPort, 5433)
        XCTAssertEqual(database.healthCheck?.retries, 5)
    }

    func testSettingsWritesShape() async throws {
        let client = try makeClient { request in
            let method = request.httpMethod ?? ""
            let path = request.url?.path ?? ""
            switch (method, path) {
            case ("PATCH", "/api/v1/applications/app-1"):
                XCTAssertTrue(queryItems(request).isEmpty)
                XCTAssertEqual(
                    bodyText(request),
                    #"{"description":"","domains":"https:\/\/a.example.com,https:\/\/b.example.com","force_domain_override":true,"health_check_enabled":true,"health_check_interval":30,"health_check_method":"GET","health_check_path":"\/health","health_check_port":8080,"health_check_return_code":200,"health_check_type":"http","is_force_https_enabled":true,"redirect":"non-www"}"#
                )
                return (200, Data(#"{"uuid":"app-1"}"#.utf8), [:])
            case ("PATCH", "/api/v1/applications/compose-1"):
                XCTAssertEqual(
                    bodyText(request),
                    #"{"docker_compose_domains":[{"domain":"https:\/\/a.example.com","name":"my_app"},{"domain":"","name":"worker"}]}"#
                )
                return (200, Data(#"{"uuid":"compose-1"}"#.utf8), [:])
            case ("PATCH", "/api/v1/databases/db-1"):
                // Only the switch and the timings. Coolify answers 422 to the HTTP fields on a database.
                XCTAssertEqual(
                    bodyText(request),
                    #"{"health_check_enabled":false,"health_check_retries":5,"is_public":true,"public_port":5433}"#)
                return (200, Data(#"{"message":"Database updated."}"#.utf8), [:])
            default:
                XCTFail("Unexpected \(method) \(path)")
                return (500, Data(), [:])
            }
        }

        try await client.updateApplication(
            "app-1",
            ApplicationUpdate(
                description: "",
                domains: "https://a.example.com,https://b.example.com",
                redirect: .nonWWW,
                isForceHTTPSEnabled: true,
                healthCheck: HealthCheck(
                    isEnabled: true, kind: .http, method: "GET", host: "", port: 8080, path: "/health",
                    returnCode: 200, interval: 30),
                forceDomainOverride: true
            )
        )
        try await client.updateApplication(
            "compose-1",
            ApplicationUpdate(dockerComposeDomains: [
                ComposeDomain(name: "my_app", domain: "https://a.example.com"),
                ComposeDomain(name: "worker", domain: ""),
            ])
        )
        try await client.updateDatabase(
            "db-1",
            DatabaseUpdate(
                isPublic: true, publicPort: 5433,
                healthCheck: HealthCheck(isEnabled: false, method: "GET", path: "/health", retries: 5))
        )
    }

    func testApplicationUpdateReadsDomainConflicts() async throws {
        let client = try makeClient { _ in
            let body = #"""
                {"message":"Domain conflicts detected. Use force_domain_override=true to proceed.",
                 "conflicts":[{"domain":"shop.example.com","resource_name":"storefront","resource_type":"service"}]}
                """#
            return (409, Data(body.utf8), [:])
        }
        do {
            try await client.updateApplication("app-1", ApplicationUpdate(domains: "https://shop.example.com"))
            XCTFail("A conflict should throw")
        } catch let error as CoolifyError {
            XCTAssertEqual(error.conflicts.map(\.domain), ["shop.example.com"])
        }
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

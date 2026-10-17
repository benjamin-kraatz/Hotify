import Foundation
import XCTest

@testable import CoolifyAPI

final class BuildSettingsTests: XCTestCase {
    // MARK: Request shape

    func testPatchSendsBuildFieldsFlatWithSnakeCaseKeys() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/applications/app-1")
            XCTAssertNil(request.url?.query)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(
                jsonBody(request),
                [
                    "install_command": "pnpm install --frozen-lockfile",
                    "build_command": "pnpm build",
                    "start_command": "pnpm start",
                    "base_directory": "/apps/web",
                    "publish_directory": "/dist",
                    "watch_paths": "apps/web/**\n!apps/web/docs/**",
                    "dockerfile_location": "/docker/Dockerfile",
                ] as NSDictionary)
            return (200, Data(#"{"uuid":"app-1"}"#.utf8), [:])
        }
        try await client.updateApplication(
            "app-1",
            ApplicationUpdate(
                build: BuildSettings(
                    installCommand: "pnpm install --frozen-lockfile",
                    buildCommand: "pnpm build",
                    startCommand: "pnpm start",
                    baseDirectory: "/apps/web",
                    publishDirectory: "/dist",
                    watchPaths: "apps/web/**\n!apps/web/docs/**",
                    dockerfileLocation: "/docker/Dockerfile")))
    }

    func testPatchSendsDeploymentCommandsWithTheirContainers() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/applications/app-1")
            XCTAssertEqual(
                jsonBody(request),
                [
                    "pre_deployment_command": "php artisan migrate --force",
                    "pre_deployment_command_container": "app",
                    "post_deployment_command": "php artisan optimize",
                    "post_deployment_command_container": "worker",
                ] as NSDictionary)
            return (200, Data(#"{"uuid":"app-1"}"#.utf8), [:])
        }
        try await client.updateApplication(
            "app-1",
            ApplicationUpdate(
                deploymentCommands: DeploymentCommands(
                    preDeployment: "php artisan migrate --force",
                    preDeploymentContainer: "app",
                    postDeployment: "php artisan optimize",
                    postDeploymentContainer: "worker")))
    }

    func testClearingSendsEmptyStringsAndTheRootForTheBaseDirectory() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(
                jsonBody(request),
                [
                    "install_command": "",
                    "publish_directory": "",
                    "watch_paths": "",
                    "base_directory": "/",
                    "pre_deployment_command": "",
                    "post_deployment_command": "",
                ] as NSDictionary)
            return (200, Data(#"{"uuid":"app-1"}"#.utf8), [:])
        }
        try await client.updateApplication(
            "app-1",
            ApplicationUpdate(
                build: BuildSettings(installCommand: "", baseDirectory: "", publishDirectory: "", watchPaths: ""),
                deploymentCommands: DeploymentCommands(
                    preDeployment: "", preDeploymentContainer: "", postDeployment: "", postDeploymentContainer: "  ")
            ))
    }

    func testBuildFieldsSitFlatBesideOtherFieldsAndStayOutWhenNil() async throws {
        let combined = try makeClient { request in
            XCTAssertEqual(
                jsonBody(request),
                [
                    "name": "site",
                    "health_check_enabled": true,
                    "limits_memory": "1g",
                    "build_command": "npm run build -- --mode=production",
                    "post_deployment_command": "npm run warm",
                ] as NSDictionary)
            return (200, Data(#"{"uuid":"app-1"}"#.utf8), [:])
        }
        try await combined.updateApplication(
            "app-1",
            ApplicationUpdate(
                name: "site",
                healthCheck: HealthCheck(isEnabled: true),
                limits: ResourceLimits(memory: "1g"),
                build: BuildSettings(buildCommand: "npm run build -- --mode=production"),
                deploymentCommands: DeploymentCommands(postDeployment: "npm run warm")))

        let omitted = try makeClient { request in
            XCTAssertEqual(jsonBody(request), ["name": "site"] as NSDictionary)
            return (200, Data(#"{"uuid":"app-1"}"#.utf8), [:])
        }
        try await omitted.updateApplication(
            "app-1", ApplicationUpdate(name: "site", build: BuildSettings(), deploymentCommands: DeploymentCommands()))
    }

    // MARK: Redeploy

    func testBuildAndDeploymentCommandsNeedARedeployButWatchPathsDoNot() {
        XCTAssertTrue(ApplicationUpdate(build: BuildSettings(baseDirectory: "/web")).needsRedeploy)
        XCTAssertTrue(ApplicationUpdate(build: BuildSettings(installCommand: "")).needsRedeploy)
        XCTAssertTrue(ApplicationUpdate(deploymentCommands: DeploymentCommands(preDeployment: "x")).needsRedeploy)

        let watchOnly = ApplicationUpdate(build: BuildSettings(watchPaths: "src/**"))
        XCTAssertFalse(watchOnly.isEmpty)
        XCTAssertFalse(watchOnly.needsRedeploy)

        XCTAssertFalse(ApplicationUpdate(deploymentCommands: DeploymentCommands()).needsRedeploy)
        XCTAssertTrue(BuildSettings().isEmpty)
        XCTAssertTrue(DeploymentCommands().isEmpty)
        XCTAssertFalse(DeploymentCommands(postDeploymentContainer: "web").isEmpty)
    }

    // MARK: Decoding

    func testApplicationDecodesBuildFieldsOfMixedShapes() throws {
        // A hand-edited row or an older instance may send a number where Coolify's columns hold strings.
        let json = #"""
            {"uuid":"app","name":"site","build_pack":"nixpacks","install_command":null,"build_command":"npm run build",
             "start_command":3000,"base_directory":"/","publish_directory":null,
             "watch_paths":"src/**\n!src/docs/**\n","dockerfile_location":null,
             "pre_deployment_command":"php artisan migrate","pre_deployment_command_container":null,
             "post_deployment_command":"","post_deployment_command_container":"worker",
             "docker_compose_location":"/docker-compose.yaml","settings":{"is_static":1}}
            """#
        let application = try CoolifyJSON.decoder().decode(Application.self, from: Data(json.utf8))
        XCTAssertEqual(
            application.build,
            BuildSettings(
                buildCommand: "npm run build", startCommand: "3000", baseDirectory: "/",
                watchPaths: "src/**\n!src/docs/**\n"))
        XCTAssertEqual(
            application.deploymentCommands,
            DeploymentCommands(
                preDeployment: "php artisan migrate", postDeployment: "", postDeploymentContainer: "worker"))
        XCTAssertEqual(application.dockerComposeLocation, "/docker-compose.yaml")
        XCTAssertEqual(application.settings?.isStatic, true)
        XCTAssertFalse(application.hasInlineDockerfile)

        let bare = #"{"uuid":"bare","name":"bare"}"#
        let missing = try CoolifyJSON.decoder().decode(Application.self, from: Data(bare.utf8))
        XCTAssertEqual(missing.build, BuildSettings())
        XCTAssertEqual(missing.deploymentCommands, DeploymentCommands())
        XCTAssertNil(missing.dockerComposeLocation)
    }

    func testInlineDockerfileShowsThroughItsContentOrCoolifysPlaceholderRepository() throws {
        let decoder = CoolifyJSON.decoder()
        let visible = #"{"uuid":"a","name":"a","build_pack":"dockerfile","dockerfile":"FROM nginx"}"#
        XCTAssertTrue(try decoder.decode(Application.self, from: Data(visible.utf8)).buildsFromInlineDockerfile)

        // A token without read:sensitive gets no `dockerfile`, only the repository Coolify filled in.
        let hidden = #"{"uuid":"b","name":"b","build_pack":"dockerfile","git_repository":"coollabsio/coolify"}"#
        XCTAssertTrue(try decoder.decode(Application.self, from: Data(hidden.utf8)).buildsFromInlineDockerfile)

        let repository = #"{"uuid":"c","name":"c","build_pack":"dockerfile","git_repository":"shop/api"}"#
        XCTAssertFalse(try decoder.decode(Application.self, from: Data(repository.utf8)).buildsFromInlineDockerfile)
    }

    // MARK: Coolify's rules

    func testShellSafeCommandFollowsCoolifysPattern() {
        for command in [
            "npm ci",
            "pnpm install --frozen-lockfile && pnpm build",
            "npm run build -- --mode=production",
            #"echo "hi there""#,
            "echo 'a;b'",
            "make build || make clean",
            "rm *.tmp",
            "! grep -q foo && echo missing",
            #"--entrypoint "sh -c 'npm start'""#,
            "echo '$HOME'",
            "bun\tinstall",
        ] {
            XCTAssertTrue(BuildSettings.isShellSafeCommand(command), command)
        }
        for command in [
            "a; b",
            "a | b",
            "a & b",
            "echo $HOME",
            #"echo "$HOME""#,
            "`x`",
            "a > b",
            "a < b",
            "(a)",
            #"a\ b"#,
            "npm ci\nnpm build",
            "npm ci\r",
            #"echo "unclosed"#,
            "",
            String(repeating: "a", count: 1_001),
        ] {
            XCTAssertFalse(BuildSettings.isShellSafeCommand(command), command)
        }
        XCTAssertTrue(BuildSettings.isShellSafeCommand(String(repeating: "a", count: 1_000)))
    }

    func testRefusedLongCommandDoesNotBacktrackWithoutEnd() {
        // Nested repetition would try every split of the word before giving up on the `;`.
        let started = Date()
        XCTAssertFalse(BuildSettings.isShellSafeCommand(String(repeating: "ab ", count: 300) + ";"))
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    func testDirectoryAndFilePathFollowCoolifysPatterns() {
        for directory in ["/", "/apps/web", "/a.b_c-d/~@+", "/dist/"] {
            XCTAssertTrue(BuildSettings.isDirectory(directory), directory)
        }
        for directory in ["", "apps", "/apps web", "/apps;rm", "/$HOME", "/" + String(repeating: "a", count: 255)] {
            XCTAssertFalse(BuildSettings.isDirectory(directory), directory)
        }
        XCTAssertTrue(BuildSettings.isFilePath("/Dockerfile"))
        XCTAssertTrue(BuildSettings.isFilePath("/docker/Dockerfile.prod"))
        XCTAssertFalse(BuildSettings.isFilePath("/"))
        XCTAssertFalse(BuildSettings.isFilePath("Dockerfile"))
        XCTAssertFalse(BuildSettings.isFilePath("/Docker file"))
    }

    func testContainerNameFollowsCoolifysPattern() {
        for name in ["web", "app-1", "my_app.worker", "9lives"] {
            XCTAssertTrue(DeploymentCommands.isContainerName(name), name)
        }
        for name in ["", "-web", ".web", "my app", "web\n", "web/1", String(repeating: "a", count: 256)] {
            XCTAssertFalse(DeploymentCommands.isContainerName(name), name)
        }
    }

    func testPathsNormalizeTheWayCoolifysFormDoes() {
        XCTAssertEqual(BuildSettings.normalizedPath(" apps/web/ "), "/apps/web")
        XCTAssertEqual(BuildSettings.normalizedPath("/"), "/")
        XCTAssertEqual(BuildSettings.normalizedPath("//"), "/")
        XCTAssertEqual(BuildSettings.normalizedPath("/dist"), "/dist")
        XCTAssertEqual(BuildSettings.normalizedPath("  "), "")
    }

    func testWatchPathsNormalizeTheWayCoolifyStoresThem() {
        XCTAssertEqual(
            BuildSettings.normalizedWatchPaths("  /src/**  \n\n! /docs/**\r\npackage.json\n"),
            "src/**\n!docs/**\npackage.json")
        XCTAssertEqual(BuildSettings.normalizedWatchPaths("\n \n"), "")
        XCTAssertEqual(BuildSettings.normalizedWatchPaths("!"), "!")
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
    BuildSettingsURLProtocol.responder = responder
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [BuildSettingsURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return try CoolifyClient(instanceURL: instanceURL, token: "test-token", session: session)
}

private final class BuildSettingsURLProtocol: URLProtocol, @unchecked Sendable {
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

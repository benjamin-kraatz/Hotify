import Foundation
import XCTest

@testable import CoolifyAPI

final class ApplicationCreateTests: XCTestCase {
    func testPublicApplicationOmitsNilFieldsAndSendsADestinationWhenSet() async throws {
        let minimal = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/applications/public")
            XCTAssertEqual(
                jsonBody(request),
                [
                    "project_uuid": "p1",
                    "server_uuid": "s1",
                    "environment_uuid": "e1",
                    "git_repository": "https://github.com/coollabsio/coolify",
                    "git_branch": "main",
                    "build_pack": "nixpacks",
                    "instant_deploy": true,
                ] as NSDictionary)
            return (201, Data(#"{"uuid":"app-1","name":"coolify","status":"exited"}"#.utf8), [:])
        }
        let created = try await minimal.createPublicApplication(
            PublicApplicationDraft(
                projectUUID: "p1", serverUUID: "s1", environmentUUID: "e1",
                gitRepository: "https://github.com/coollabsio/coolify", gitBranch: "main", buildPack: .nixpacks))
        XCTAssertEqual(created.uuid, "app-1")

        let placed = try makeClient { request in
            XCTAssertEqual(
                jsonBody(request),
                [
                    "project_uuid": "p1",
                    "server_uuid": "s1",
                    "environment_uuid": "e1",
                    "destination_uuid": "d1",
                    "name": "shop",
                    "description": "Storefront",
                    "ports_exposes": "3000",
                    "instant_deploy": true,
                    "git_repository": "https://github.com/acme/shop",
                    "git_branch": "develop",
                    "build_pack": "dockerfile",
                    "domains": "https://shop.example.com",
                    "dockerfile_location": "/docker/Dockerfile",
                    "docker_compose_location": "/docker-compose.yaml",
                ] as NSDictionary)
            return (201, Data(#"{"uuid":"app-2"}"#.utf8), [:])
        }
        let full = try await placed.createPublicApplication(
            PublicApplicationDraft(
                projectUUID: "p1", serverUUID: "s1", environmentUUID: "e1", destinationUUID: "d1", name: "shop",
                description: "Storefront", portsExposes: "3000", gitRepository: "https://github.com/acme/shop",
                gitBranch: "develop", buildPack: .dockerfile, domains: "https://shop.example.com",
                dockerfileLocation: "/docker/Dockerfile", dockerComposeLocation: "/docker-compose.yaml"))
        XCTAssertEqual(full.uuid, "app-2")
    }

    func testDockerfileApplicationSendsTheDockerfileAndNoDestination() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/applications/dockerfile")
            XCTAssertEqual(
                jsonBody(request),
                [
                    "project_uuid": "p1",
                    "server_uuid": "s1",
                    "environment_uuid": "e1",
                    "instant_deploy": false,
                    "dockerfile": "FROM alpine\nCMD [\"echo\", \"hi\"]",
                    "build_pack": "dockerfile",
                ] as NSDictionary)
            return (201, Data(#"{"uuid":"app-3"}"#.utf8), [:])
        }
        let created = try await client.createDockerfileApplication(
            DockerfileApplicationDraft(
                projectUUID: "p1", serverUUID: "s1", environmentUUID: "e1", instantDeploy: false,
                dockerfile: "FROM alpine\nCMD [\"echo\", \"hi\"]"))
        XCTAssertEqual(created.uuid, "app-3")
    }

    func testDockerImageApplicationOmitsTagBuildPackAndDestination() async throws {
        let named = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/applications/dockerimage")
            XCTAssertEqual(
                jsonBody(request),
                [
                    "project_uuid": "p1",
                    "server_uuid": "s1",
                    "environment_uuid": "e1",
                    "name": "whoami",
                    "ports_exposes": "80",
                    "instant_deploy": true,
                    "docker_registry_image_name": "traefik/whoami",
                    "docker_registry_image_tag": "v1.11.0",
                ] as NSDictionary)
            return (201, Data(#"{"uuid":"app-4"}"#.utf8), [:])
        }
        _ = try await named.createDockerImageApplication(
            DockerImageApplicationDraft(
                projectUUID: "p1", serverUUID: "s1", environmentUUID: "e1", name: "whoami", portsExposes: "80",
                dockerRegistryImageName: "traefik/whoami", dockerRegistryImageTag: "v1.11.0"))

        let plain = try makeClient { request in
            XCTAssertEqual(
                jsonBody(request),
                [
                    "project_uuid": "p1",
                    "server_uuid": "s1",
                    "environment_uuid": "e1",
                    "instant_deploy": true,
                    "docker_registry_image_name": "nginx",
                ] as NSDictionary)
            return (201, Data(#"{"uuid":"app-5"}"#.utf8), [:])
        }
        let created = try await plain.createDockerImageApplication(
            DockerImageApplicationDraft(
                projectUUID: "p1", serverUUID: "s1", environmentUUID: "e1", dockerRegistryImageName: "nginx"))
        XCTAssertEqual(created.uuid, "app-5")
    }

    func testPrivateGitHubAppApplication() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/applications/private-github-app")
            XCTAssertEqual(
                jsonBody(request),
                [
                    "project_uuid": "p1",
                    "server_uuid": "s1",
                    "environment_uuid": "e1",
                    "instant_deploy": true,
                    "github_app_uuid": "gh-1",
                    "git_repository": "acme/shop",
                    "git_branch": "main",
                    "build_pack": "dockercompose",
                ] as NSDictionary)
            return (201, Data(#"{"uuid":"app-6"}"#.utf8), [:])
        }
        let created = try await client.createPrivateGitHubAppApplication(
            PrivateGitHubAppApplicationDraft(
                projectUUID: "p1", serverUUID: "s1", environmentUUID: "e1", githubAppUUID: "gh-1",
                gitRepository: "acme/shop", gitBranch: "main", buildPack: .dockercompose))
        XCTAssertEqual(created.uuid, "app-6")
    }

    func testDeployKeyApplicationOmitsNilDestination() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/applications/private-deploy-key")
            XCTAssertEqual(
                jsonBody(request),
                [
                    "project_uuid": "p1",
                    "server_uuid": "s1",
                    "environment_uuid": "e1",
                    "instant_deploy": true,
                    "private_key_uuid": "key-1",
                    "git_repository": "git@github.com:acme/shop.git",
                    "git_branch": "main",
                    "build_pack": "static",
                ] as NSDictionary)
            return (201, Data(#"{"uuid":"app-7"}"#.utf8), [:])
        }
        let created = try await client.createDeployKeyApplication(
            DeployKeyApplicationDraft(
                projectUUID: "p1", serverUUID: "s1", environmentUUID: "e1", privateKeyUUID: "key-1",
                gitRepository: "git@github.com:acme/shop.git", gitBranch: "main", buildPack: .static))
        XCTAssertEqual(created.uuid, "app-7")
    }

    func testGitHubAppsRepositoriesAndBranches() async throws {
        let client = try makeClient { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/v1/github-apps"):
                return (
                    200,
                    Data(
                        """
                        [{
                          "id": "4",
                          "uuid": "gh-1",
                          "name": "Hotify",
                          "organization": null,
                          "client_secret": "should-not-be-kept",
                          "is_public": 1
                        }]
                        """.utf8), [:]
                )
            case ("GET", "/api/v1/github-apps/4/repositories"):
                return (
                    200,
                    Data(
                        """
                        {"repositories":[{
                          "id": 9,
                          "name": "shop",
                          "full_name": "acme/shop",
                          "private": 1,
                          "default_branch": "main",
                          "html_url": "https://github.com/acme/shop"
                        }, {
                          "name": "web",
                          "owner": {"login": "acme"}
                        }]}
                        """.utf8), [:]
                )
            default:
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(
                    request.url?.absoluteString,
                    "http://coolify.example:8000/api/v1/github-apps/4/repositories/acme/my%20app/branches")
                return (
                    200,
                    Data(#"{"branches":["main",{"name":"develop","protected":0}]}"#.utf8), [:]
                )
            }
        }

        let apps = try await client.githubApps()
        XCTAssertEqual(apps.map(\.id), [4])
        XCTAssertEqual(apps.first?.uuid, "gh-1")
        XCTAssertEqual(apps.first?.name, "Hotify")
        XCTAssertNil(apps.first?.organization)
        XCTAssertFalse(String(describing: apps.first).contains("should-not-be-kept"))

        let repositories = try await client.githubRepositories(appID: 4)
        XCTAssertEqual(repositories.map(\.fullName), ["acme/shop", "acme/web"])
        XCTAssertEqual(repositories.first?.isPrivate, true)
        XCTAssertEqual(repositories.first?.defaultBranch, "main")
        XCTAssertEqual(repositories.last?.owner, "acme")
        XCTAssertEqual(repositories.last?.repositoryName, "web")

        let branches = try await client.githubBranches(appID: 4, owner: "acme", repo: "my app")
        XCTAssertEqual(branches.map(\.name), ["main", "develop"])
    }

    func testPrivateKeysKeepOnlyUUIDAndName() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/security/keys")
            return (
                200,
                Data(
                    """
                    [{
                      "uuid": "key-1",
                      "name": "deploy",
                      "private_key": "should-not-be-kept",
                      "public_key": "ssh-ed25519 AAAA",
                      "is_git_related": 1
                    }]
                    """.utf8), [:]
            )
        }
        let keys = try await client.privateKeys()
        XCTAssertEqual(keys.map(\.uuid), ["key-1"])
        XCTAssertEqual(keys.first?.name, "deploy")
        XCTAssertFalse(String(describing: keys.first).contains("should-not-be-kept"))
        XCTAssertFalse(String(describing: keys.first).contains("ssh-ed25519"))
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
    ApplicationCreateURLProtocol.responder = responder
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ApplicationCreateURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return try CoolifyClient(instanceURL: instanceURL, token: "test-token", session: session)
}

private final class ApplicationCreateURLProtocol: URLProtocol, @unchecked Sendable {
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

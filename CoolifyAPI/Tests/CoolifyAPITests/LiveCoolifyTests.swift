import Foundation
import XCTest

@testable import CoolifyAPI

final class LiveCoolifyTests: XCTestCase {
    func testDemoInstanceReads() async throws {
        let environment = liveEnvironment()
        try XCTSkipIf(environment["COOLIFY_LIVE_TESTS"] != "1")
        guard let baseURL = environment["COOLIFY_DEMO_INSTANCE_BASE_URL"], !baseURL.isEmpty,
            let token = environment["COOLIFY_DEMO_INSTANCE_API_KEY"], !token.isEmpty
        else {
            throw XCTSkip("COOLIFY_DEMO_INSTANCE_BASE_URL and COOLIFY_DEMO_INSTANCE_API_KEY are not set")
        }

        let client = try CoolifyClient(instanceURL: baseURL, token: token)
        let version = try await client.version()
        let health = try await client.health()
        XCTAssertEqual(health, "OK")
        XCTAssertFalse(version.isEmpty)

        let team = try await client.currentTeam()
        XCTAssertFalse(team.name.isEmpty)
        let teams = try await client.teams()
        XCTAssertFalse(teams.isEmpty)

        let projects = try await client.projects()
        XCTAssertFalse(projects.isEmpty)
        let project = try await client.project(projects[0].uuid)
        XCTAssertFalse(project.environments?.isEmpty ?? true)

        let servers = try await client.servers()
        XCTAssertFalse(servers.isEmpty)
        XCTAssertNotNil(servers[0].isReachable)
        let serverResources = try await client.resources(onServer: servers[0].uuid)

        let applications = try await client.applications()
        let services = try await client.services()
        let databases = try await client.databases()
        let inventory = try await client.resources()
        let deployments = try await client.runningDeployments()

        XCTAssertFalse(services.isEmpty)
        XCTAssertFalse(inventory.isEmpty)
        for service in services {
            XCTAssertFalse(service.uuid.isEmpty)
            XCTAssertNotNil(service.status)
        }
        XCTAssertFalse(services.flatMap { $0.applications ?? [] }.isEmpty)

        print("Coolify \(version) health=\(health) team=\(team.name)")
        print("projects=\(projects.count) servers=\(servers.count) serverResources=\(serverResources.count)")
        print(
            "applications=\(applications.count) services=\(services.count) databases=\(databases.count) inventory=\(inventory.count) runningDeployments=\(deployments.count)"
        )
        for service in services {
            let containers = (service.applications ?? []).map { "\($0.name):\($0.status ?? "unknown")" }.joined(
                separator: ", ")
            print("service \(service.serviceType ?? service.name) \(service.status ?? "unknown") [\(containers)]")
        }
    }
}

private func liveEnvironment() -> [String: String] {
    var values = ProcessInfo.processInfo.environment
    guard values["COOLIFY_LIVE_TESTS"] == "1" else { return values }
    var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    for _ in 0..<5 {
        let file = directory.appendingPathComponent(".env")
        if let text = try? String(contentsOf: file, encoding: .utf8) {
            for line in text.split(whereSeparator: \.isNewline) {
                let raw = line.trimmingCharacters(in: .whitespaces)
                guard !raw.isEmpty, !raw.hasPrefix("#") else { continue }
                let parts = raw.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                var value = parts[1].trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                }
                if values[key] == nil || values[key]?.isEmpty == true {
                    values[key] = value
                }
            }
            break
        }
        directory.deleteLastPathComponent()
    }
    return values
}

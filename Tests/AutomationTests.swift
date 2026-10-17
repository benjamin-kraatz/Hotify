import CoolifyAPI
import Foundation
import SwiftUI

// Checks that Shortcut automations run once for a change Hotify saw happen, never for the first look, a repeat look,
// or an edit, and that the input they get holds no secrets. Run with scripts/test_automations.sh.

// Xcode generates these from the asset catalog, which this build leaves out.
extension Color {
    static let ember = Color.red
    static let glow = Color.orange
}

/// Answers the instance watch's requests from `MockCoolify.state`.
final class MockCoolify: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var running: [[String: Any]] = []
    nonisolated(unsafe) static var ended: [String: [String: Any]] = [:]
    nonisolated(unsafe) static var applications: [[String: Any]] = []
    nonisolated(unsafe) static var requests: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.requests.append(path)
        let body: Any =
            switch path {
            case "/api/v1/applications": Self.applications
            case "/api/v1/deployments": Self.running
            case let path where path.hasPrefix("/api/v1/deployments/"):
                Self.ended[String(path.dropFirst("/api/v1/deployments/".count))] ?? [:]
            default: [Any]()
            }
        let data = try! JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

func check(_ condition: Bool, _ message: String) {
    if !condition {
        print("FAIL: \(message)")
        exit(1)
    }
    print("ok - \(message)")
}

func makeClient() throws -> CoolifyClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockCoolify.self]
    return try CoolifyClient(
        instanceURL: "https://coolify.example.com", token: "secret-token-123",
        session: URLSession(configuration: configuration))
}

@main
struct AutomationTests {
    static func main() async throws {
        try await watchFeedsAutomationsOnlyRealChanges()
        dispatcherRunsOncePerChangeAndCapsBursts()
        matchingFollowsScopeAndTrigger()
        eligibilityIsSeparateFromNotifications()
        shortcutURLEncodesStrictlyAndCarriesNoSecrets()
        print("All automation checks passed.")
    }

    static let instanceID = UUID()

    static func automation(
        _ trigger: AutomationTrigger, resource: ResourceRoute? = nil, isEnabled: Bool = true
    ) -> ShortcutAutomation {
        ShortcutAutomation(
            shortcutName: "Ping", instanceID: instanceID,
            resource: resource.map { ShortcutAutomation.Resource(route: $0, name: "web") }, trigger: trigger,
            isEnabled: isEnabled)
    }

    /// The first look sets the baseline, a deploy seen running and then ended runs once, and looking again changes
    /// nothing.
    static func watchFeedsAutomationsOnlyRealChanges() async throws {
        let client = try makeClient()
        MockCoolify.applications = [["id": 7, "uuid": "web", "name": "web", "status": "running:healthy"]]
        // Already running when Hotify first looks, and one that ended before then, which Hotify never sees.
        MockCoolify.running = [["deployment_uuid": "d1", "application_id": 7, "status": "in_progress"]]
        MockCoolify.ended = [
            "d0": ["deployment_uuid": "d0", "application_id": 7, "status": "finished"],
            "d1": [
                "deployment_uuid": "d1", "application_id": 7, "status": "finished", "commit": "528a020",
                "commit_message": "Ship it\n\nLonger body", "logs": "[{\"output\":\"SECRET_KEY=abc\"}]",
            ],
        ]
        var watch = InstanceWatch()
        var dispatcher = AutomationDispatcher()
        let succeeded = automation(.deploymentSucceeded, resource: .application("web"))

        let first = await watch.check(client: client, instanceID: instanceID)
        check(first.isEmpty, "the first look only sets the baseline")
        check(
            dispatcher.runs(for: first, automations: [succeeded]).runs.isEmpty, "nothing runs for the baseline")

        MockCoolify.running = []
        let second = await watch.check(client: client, instanceID: instanceID)
        check(second.count == 1 && second[0].deploymentID == "d1", "the deploy that ended is reported once")
        check(second[0].event == .deploymentFinishedElsewhere, "a deploy this device didn't start reads as elsewhere")
        let runs = dispatcher.runs(for: second, automations: [succeeded]).runs
        check(runs.count == 1, "the automation runs for the deploy it saw end")

        let third = await watch.check(client: client, instanceID: instanceID)
        check(third.isEmpty, "a repeat look reports nothing")
        check(
            dispatcher.runs(for: second, automations: [succeeded]).runs.isEmpty,
            "the same change seen again doesn't run twice")

        let payload = ShortcutPayload(
            notice: second[0], trigger: .deploymentSucceeded, instanceName: "Home",
            instanceURL: URL(string: "https://user:pass@coolify.example.com:8443/base")!)
        let json = payload.json
        check(!json.contains("secret-token-123"), "the token never reaches the Shortcut")
        check(!json.contains("SECRET_KEY") && !json.contains("logs"), "build logs never reach the Shortcut")
        check(!json.contains("pass") && json.contains("\"host\":\"coolify.example.com:8443\""), "only host and port")
        check(json.contains("\"commitMessage\":\"Ship it\""), "the commit message is cut to its first line")
        check(json.contains("\"event\":\"deployment.succeeded\"") && json.contains("\"test\":false"), "event named")
    }

    static func notice(
        _ event: NotificationEvent, route: ResourceRoute? = .application("web"), key: String? = nil,
        pullRequest: Int = 0
    ) -> Notice {
        Notice(
            instanceID: instanceID, event: event, title: "web", body: "Deployed.", route: route,
            pullRequest: pullRequest, eventKey: key)
    }

    static func dispatcherRunsOncePerChangeAndCapsBursts() {
        var dispatcher = AutomationDispatcher()
        let any = automation(.deploymentSucceeded)
        let start = Date(timeIntervalSince1970: 1_000_000)
        let burst = (1...5).map { notice(.deploymentFinished, key: "deployment/\($0)") }
        let result = dispatcher.runs(for: burst, automations: [any], at: start)
        check(result.runs.count == AutomationDispatcher.burstLimit, "a burst runs at most the limit")
        check(result.skipped.count == 2, "the rest of a burst is held back and recorded")
        check(
            dispatcher.runs(for: burst, automations: [any], at: start.addingTimeInterval(120)).runs.isEmpty,
            "held-back changes don't run later as a replay")
        let later = dispatcher.runs(
            for: [notice(.deploymentFinished, key: "deployment/6")], automations: [any],
            at: start.addingTimeInterval(120))
        check(later.runs.count == 1, "a new change runs once the minute has passed")

        let down = notice(.resourceDown)
        var outages = AutomationDispatcher()
        let stopped = automation(.resourceDown)
        check(outages.runs(for: [down], automations: [stopped], at: start).runs.count == 1, "an outage runs")
        check(
            outages.runs(for: [down], automations: [stopped], at: start.addingTimeInterval(10)).runs.isEmpty,
            "the same outage within its minute doesn't run twice")
        check(
            outages.runs(for: [down], automations: [stopped], at: start.addingTimeInterval(600)).runs.count == 1,
            "a later outage runs again")
    }

    static func matchingFollowsScopeAndTrigger() {
        let finished = notice(.deploymentFinished, key: "deployment/a")
        check(automation(.deploymentSucceeded).answers(finished), "any resource answers")
        check(
            automation(.deploymentSucceeded).answers(notice(.deploymentFinishedElsewhere)),
            "a deploy from a push counts as succeeded")
        check(
            automation(.deploymentSucceeded, resource: .application("web")).answers(finished), "its own resource")
        check(
            !automation(.deploymentSucceeded, resource: .application("api")).answers(finished),
            "another resource doesn't answer")
        check(!automation(.deploymentFailed).answers(finished), "another event doesn't answer")
        check(!automation(.deploymentSucceeded, isEnabled: false).answers(finished), "a switched-off one doesn't")
        check(!automation(.manual).answers(finished), "a manual one never runs by itself")
        check(
            !automation(.deploymentSucceeded).answers(notice(.deploymentFinished, pullRequest: 12)),
            "previews don't count")
        var other = automation(.deploymentSucceeded)
        other.instanceID = UUID()
        check(!other.answers(finished), "another instance doesn't answer")
        check(
            automation(.backupFailed, resource: .application("web")).problem != nil,
            "an application can't have a backup event")
    }

    static func eligibilityIsSeparateFromNotifications() {
        let store = AutomationStore(defaults: nil, automations: [automation(.manual)])
        check(!store.observes(instanceID), "a manual automation doesn't keep the instance watched")
        store.save(automation(.deploymentFailed))
        check(store.observes(instanceID), "an automatic one watches its instance, without notifications")
        check(!store.observes(UUID()), "other instances stay unwatched")
        for automation in store.automations { store.setEnabled(false, for: automation.id) }
        check(!store.observes(instanceID), "switched off, it stops watching")

        let suite = "Hotify.AutomationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let saved = AutomationStore(defaults: defaults)
        saved.save(automation(.deploymentSucceeded))
        check(AutomationStore(defaults: defaults).automations.count == 1, "automations persist on the device")
        check(
            defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("hotify.automations") }.count == 2,
            "they live under hotify. keys in the device's own defaults")
    }

    static func shortcutURLEncodesStrictlyAndCarriesNoSecrets() {
        let url = ShortcutLink.run(" Deploy + Ping & Co ", text: #"{"a":"b=c&d+e?f/g #h"}"#)!
        let query = url.absoluteString.split(separator: "?", maxSplits: 1).last.map(String.init) ?? ""
        check(url.scheme == "shortcuts" && url.host() == "run-shortcut", "uses run-shortcut")
        check(
            query
                == "name=Deploy%20%2B%20Ping%20%26%20Co&input=text&text=%7B%22a%22%3A%22b%3Dc%26d%2Be%3Ff%2Fg%20%23h%22%7D",
            "every reserved character is encoded, including +")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        check(items.first { $0.name == "text" }?.value == #"{"a":"b=c&d+e?f/g #h"}"#, "the text decodes back")
        check(ShortcutLink.run("   ", text: "{}") == nil, "an empty name has no URL")
        check(ShortcutLink.open("Ping")?.absoluteString == "shortcuts://open-shortcut?name=Ping", "opens by name")
    }
}

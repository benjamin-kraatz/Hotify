import Foundation

/// What a Shortcut receives as its input text: one JSON object about the event. It holds names, ids, and links only.
/// API tokens, environment variables, and build or container logs never go in, since the text ends up in a URL and
/// in the Shortcut's own history.
struct ShortcutPayload: Encodable, Hashable {
    /// Bumped if a field changes meaning, so a Shortcut can check what it reads.
    var version = 1
    /// Such as `deployment.succeeded`. See `AutomationTrigger.payloadName`.
    var event: String
    /// Set when you ran it from Hotify by hand, to try it out.
    var isTest: Bool
    var occurredAt: Date
    var instance: Instance
    var resource: Resource?
    var deployment: Deployment?
    /// One line about what happened, such as "Deployed." or "Turned unhealthy."
    var summary: String?
    /// Opens the resource, or the deployment, in Hotify.
    var link: String?

    struct Instance: Encodable, Hashable {
        var name: String
        /// The host and port only. The rest of the address could carry a sign-in.
        var host: String
    }

    struct Resource: Encodable, Hashable {
        var name: String
        var kind: String
        var uuid: String
        var project: String?
        var environment: String?
    }

    struct Deployment: Encodable, Hashable {
        var uuid: String
        var commit: String?
        /// The first line of the commit message.
        var commitMessage: String?
    }

    enum CodingKeys: String, CodingKey {
        case version, event, occurredAt, instance, resource, deployment, summary, link
        case isTest = "test"
    }

    /// The longest commit subject sent along. The whole payload rides in a URL.
    static let commitMessageLimit = 200

    static func host(of url: URL) -> String {
        guard let host = url.host(), !host.isEmpty else { return "" }
        return url.port.map { "\(host):\($0)" } ?? host
    }

    /// The payload for a change the instance watch saw.
    init(notice: Notice, trigger: AutomationTrigger, instanceName: String, instanceURL: URL, at date: Date = .now) {
        event = trigger.payloadName
        isTest = false
        occurredAt = date
        instance = Instance(name: instanceName, host: Self.host(of: instanceURL))
        if let route = notice.route {
            resource = Resource(
                name: notice.title, kind: route.key, uuid: route.uuid,
                project: notice.place?.projectName,
                environment: notice.place.flatMap { $0.environmentName.isEmpty ? nil : $0.environmentName })
        }
        if let id = notice.deploymentID {
            deployment = Deployment(
                uuid: id, commit: notice.commit, commitMessage: Self.subject(of: notice.commitMessage))
        }
        summary = notice.body.components(separatedBy: .newlines).first
        link = notice.link?.absoluteString
    }

    /// The payload for a run from Hotify by hand.
    init(
        testing automation: ShortcutAutomation, instanceName: String, instanceURL: URL, at date: Date = .now
    ) {
        event = automation.trigger.payloadName
        isTest = true
        occurredAt = date
        instance = Instance(name: instanceName, host: Self.host(of: instanceURL))
        if let resource = automation.resource, let route = resource.route {
            self.resource = Resource(name: resource.name, kind: route.key, uuid: route.uuid)
            link = ResourceLink(instanceID: automation.instanceID, route: route).url.absoluteString
        } else {
            link = InstanceLink(instanceID: automation.instanceID).url.absoluteString
        }
        summary = automation.trigger.isAutomatic ? "A test run from Hotify." : "Run from Hotify."
    }

    /// The text the Shortcut gets: compact, keys sorted, dates in ISO 8601.
    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func subject(of message: String?) -> String? {
        guard
            let line = message?.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces),
            !line.isEmpty
        else { return nil }
        return line.count > commitMessageLimit ? String(line.prefix(commitMessageLimit)) + "…" : line
    }
}

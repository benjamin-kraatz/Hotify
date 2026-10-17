import Foundation

/// Decides which automations run for the changes one look at an instance turned up. It only sees changes the instance
/// watch reports, which already skip the first look and anything older, and it runs each automation at most once per
/// change and a few times a minute, so a burst of deploys doesn't open Shortcuts over and over.
struct AutomationDispatcher {
    /// One Shortcut to open, and the change that called for it.
    struct Run: Hashable {
        var automation: ShortcutAutomation
        var notice: Notice
    }

    /// An automation that matched but was held back, since it already ran too often in the last minute.
    struct Skip: Hashable {
        var automation: ShortcutAutomation
        var notice: Notice
    }

    static let burstLimit = 3
    static let burstWindow: TimeInterval = 60
    /// How long a change counts as handled. Longer than any deploy stays in Coolify's running list.
    static let memory: TimeInterval = 6 * 3_600

    private var handled: [String: Date] = [:]
    private var recent: [UUID: [Date]] = [:]

    mutating func runs(for notices: [Notice], automations: [ShortcutAutomation], at now: Date = .now)
        -> (runs: [Run], skipped: [Skip])
    {
        handled = handled.filter { now.timeIntervalSince($0.value) < Self.memory }
        var runs: [Run] = []
        var skipped: [Skip] = []
        for notice in notices {
            for automation in automations where automation.answers(notice) {
                let key = "\(automation.id.uuidString)|\(Self.key(for: notice, at: now))"
                guard handled[key] == nil else { continue }
                handled[key] = now
                let window = (recent[automation.id] ?? []).filter { now.timeIntervalSince($0) < Self.burstWindow }
                guard window.count < Self.burstLimit else {
                    recent[automation.id] = window
                    skipped.append(Skip(automation: automation, notice: notice))
                    continue
                }
                recent[automation.id] = window + [now]
                runs.append(Run(automation: automation, notice: notice))
            }
        }
        return (runs, skipped)
    }

    /// Names a change. A deploy and a backup run have their own ids. A resource going down has none, so the minute it
    /// was seen stands in, which still tells two outages apart.
    static func key(for notice: Notice, at now: Date) -> String {
        if let key = notice.eventKey { return key }
        let minute = Int(now.timeIntervalSince1970 / 60)
        let subject = notice.route.map { "\($0.key)/\($0.uuid)" } ?? notice.title
        return "\(notice.event.rawValue)/\(subject)/\(notice.body)/\(minute)"
    }
}

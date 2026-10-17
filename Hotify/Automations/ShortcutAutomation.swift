import Foundation

/// A Shortcut this device runs by name when something happens on one instance, or when you tap Run. It is kept on
/// this device alone, so a second Mac or an iPhone never runs it too.
struct ShortcutAutomation: Identifiable, Codable, Hashable {
    var id = UUID()
    /// The Shortcut's name, exactly as the Shortcuts app shows it.
    var shortcutName: String
    var instanceID: UUID
    /// One resource, or `nil` for every resource on the instance the trigger applies to.
    var resource: Resource?
    var trigger: AutomationTrigger
    var isEnabled = true

    /// The resource an automation is about. The name is what it was called when the automation was saved, for
    /// showing it. Matching goes by the route alone.
    struct Resource: Codable, Hashable {
        var kind: String
        var uuid: String
        var name: String

        init(route: ResourceRoute, name: String) {
            kind = route.key
            uuid = route.uuid
            self.name = name
        }

        var route: ResourceRoute? { ResourceRoute(key: kind, uuid: uuid) }
    }

    var trimmedShortcutName: String { shortcutName.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Whether Hotify runs it by itself on this device. An automation saved with an automatic trigger on a Mac stays
    /// on the Mac, but the check keeps any other device from acting on one.
    var runsAutomatically: Bool {
        isEnabled && trigger.isAutomatic && AutomationTrigger.available.contains(trigger)
    }

    /// Whether this automation answers a change the instance watch saw.
    func answers(_ notice: Notice) -> Bool {
        guard runsAutomatically, notice.instanceID == instanceID, trigger.answers(notice.event) else { return false }
        // A preview's deploy leaves production as it was.
        if notice.pullRequest > 0 { return false }
        guard let resource else { return true }
        return notice.route != nil && notice.route == resource.route
    }

    /// The first thing that keeps it from saving.
    var problem: String? {
        if trimmedShortcutName.isEmpty { return "Name the Shortcut to run." }
        if let kind = resource?.route?.kind, !trigger.applies(to: kind) {
            return "A \(kind.title.lowercased()) can't have that event. Pick another event or resource."
        }
        return nil
    }
}

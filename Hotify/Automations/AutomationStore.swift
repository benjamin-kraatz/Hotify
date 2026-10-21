import Foundation

/// The Shortcut automations of this device, and what each one did last.
///
/// They live in this device's own defaults, never in iCloud key-value storage or the App Group. An automation runs
/// wherever it is saved, so syncing it would have a second Mac run the same Shortcut for the same deploy.
@Observable
final class AutomationStore {
    private(set) var automations: [ShortcutAutomation]
    /// The last time each automation opened its Shortcut, or tried to.
    private(set) var lastRuns: [UUID: LastRun]

    /// One attempt to open a Shortcut. Hotify only learns whether Shortcuts took the link, not how the Shortcut did.
    struct LastRun: Codable, Hashable {
        var date: Date
        /// The trigger's title, or "Test run".
        var reason: String
        var resourceName: String?
        /// Why it didn't open. `nil` when Shortcuts took it.
        var failure: String?
        /// Set when it matched but ran too often in the last minute.
        var wasSkipped = false
    }

    private let defaults: UserDefaults?
    private static let automationsKey = "hotify.automations.v1"
    private static let lastRunsKey = "hotify.automations.lastRuns.v1"

    /// `defaults: nil` keeps everything in memory, as previews and fixtures do.
    init(defaults: UserDefaults? = .standard, automations: [ShortcutAutomation] = []) {
        self.defaults = defaults
        let decoder = JSONDecoder()
        self.automations =
            defaults?.data(forKey: Self.automationsKey).flatMap {
                try? decoder.decode([ShortcutAutomation].self, from: $0)
            } ?? automations
        lastRuns =
            defaults?.data(forKey: Self.lastRunsKey).flatMap {
                try? decoder.decode([UUID: LastRun].self, from: $0)
            } ?? [:]
    }

    /// Whether the instance watch needs to look at an instance for these automations, apart from notifications.
    func observes(_ instance: UUID) -> Bool {
        automations.contains { $0.instanceID == instance && $0.runsAutomatically }
    }

    func automations(for instance: UUID) -> [ShortcutAutomation] {
        automations.filter { $0.instanceID == instance }
    }

    /// Adds the automation, or replaces the one with its id.
    func save(_ automation: ShortcutAutomation) {
        var automation = automation
        automation.shortcutName = automation.trimmedShortcutName
        if let index = automations.firstIndex(where: { $0.id == automation.id }) {
            automations[index] = automation
        } else {
            automations.append(automation)
        }
        persist()
    }

    func setEnabled(_ isEnabled: Bool, for id: UUID) {
        guard let index = automations.firstIndex(where: { $0.id == id }) else { return }
        automations[index].isEnabled = isEnabled
        persist()
    }

    func remove(_ id: UUID) {
        automations.removeAll { $0.id == id }
        lastRuns[id] = nil
        persist()
    }

    func record(_ run: LastRun, for id: UUID) {
        guard automations.contains(where: { $0.id == id }) else { return }
        lastRuns[id] = run
        persist()
    }

    private func persist() {
        guard let defaults else { return }
        let encoder = JSONEncoder()
        defaults.set(try? encoder.encode(automations), forKey: Self.automationsKey)
        defaults.set(try? encoder.encode(lastRuns), forKey: Self.lastRunsKey)
    }
}

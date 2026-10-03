import Foundation
import UserNotifications

/// Which instances notify, and about what. Each instance is off until turned on, which is when Hotify asks the system
/// for permission. Its events then start from their defaults.
@Observable
final class NotificationSettings {
    private(set) var enabledInstances: Set<UUID>
    /// The events turned on per instance. An instance missing here has the defaults.
    private var events: [UUID: Set<NotificationEvent>]
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private let defaults: UserDefaults?
    private static let instancesKey = "hotify.notifications.instances"
    private static let eventsKey = "hotify.notifications.events"

    /// `defaults: nil` keeps everything in memory, as previews and fixtures do.
    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        enabledInstances = Set((defaults?.stringArray(forKey: Self.instancesKey) ?? []).compactMap(UUID.init))
        let stored = defaults?.dictionary(forKey: Self.eventsKey) as? [String: [String]] ?? [:]
        events = stored.reduce(into: [:]) { result, entry in
            guard let id = UUID(uuidString: entry.key) else { return }
            result[id] = Set(entry.value.compactMap(NotificationEvent.init(rawValue:)))
        }
    }

    func isEnabled(_ instance: UUID) -> Bool {
        enabledInstances.contains(instance)
    }

    func isOn(_ event: NotificationEvent, for instance: UUID) -> Bool {
        isEnabled(instance) && (events[instance] ?? Self.defaultEvents).contains(event)
    }

    /// Whether the event's own switch is on, whatever the instance's.
    func isChosen(_ event: NotificationEvent, for instance: UUID) -> Bool {
        (events[instance] ?? Self.defaultEvents).contains(event)
    }

    /// Turns an instance on or off. Turning one on asks for permission the first time.
    func setEnabled(_ isEnabled: Bool, for instance: UUID) async {
        if isEnabled {
            enabledInstances.insert(instance)
            await requestAuthorizationIfNeeded()
        } else {
            enabledInstances.remove(instance)
        }
        persist()
    }

    func set(_ event: NotificationEvent, _ isOn: Bool, for instance: UUID) {
        var chosen = events[instance] ?? Self.defaultEvents
        if isOn { chosen.insert(event) } else { chosen.remove(event) }
        events[instance] = chosen
        persist()
    }

    /// Drops what a removed instance left behind.
    func forget(_ instance: UUID) {
        enabledInstances.remove(instance)
        events[instance] = nil
        persist()
    }

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func requestAuthorizationIfNeeded() async {
        await refreshAuthorization()
        guard authorization == .notDetermined else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refreshAuthorization()
    }

    private static var defaultEvents: Set<NotificationEvent> {
        Set(NotificationEvent.allCases.filter(\.isOnByDefault))
    }

    private func persist() {
        guard let defaults else { return }
        defaults.set(enabledInstances.map(\.uuidString).sorted(), forKey: Self.instancesKey)
        defaults.set(
            Dictionary(uniqueKeysWithValues: events.map { ($0.key.uuidString, $0.value.map(\.rawValue).sorted()) }),
            forKey: Self.eventsKey)
    }
}

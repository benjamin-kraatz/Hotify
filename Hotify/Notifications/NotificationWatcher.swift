import CoolifyAPI
import Foundation

/// Looks at every instance whose notifications are on, or that a Shortcut automation of this Mac waits on, every 30
/// seconds while Hotify runs. It posts what changed where notifications want it, and hands every change to the
/// automations. It only runs while Hotify does, so on the Mac the menu bar companion keeps it going after the windows
/// close.
final class NotificationWatcher {
    private let poster = NotificationPoster()
    private var watches: [UUID: InstanceWatch] = [:]
    private var task: Task<Void, Never>?

    func start(store: InstanceStore, settings: NotificationSettings, automations: AutomationRunner) {
        task?.cancel()
        poster.registerCategories()
        task = Task { [weak self] in
            await settings.refreshAuthorization()
            while !Task.isCancelled {
                await self?.checkAll(store: store, settings: settings, automations: automations)
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }

    /// Whether anything wants the instance watched. Automations don't need notifications or their permission.
    private static func isWatched(_ instance: UUID, settings: NotificationSettings, automations: AutomationRunner)
        -> Bool
    {
        settings.isEnabled(instance) || automations.store.observes(instance)
    }

    private func checkAll(store: InstanceStore, settings: NotificationSettings, automations: AutomationRunner) async {
        // An instance nothing watches starts from a fresh baseline when something watches it again.
        watches = watches.filter { Self.isWatched($0.key, settings: settings, automations: automations) }
        for instance in store.instances
        where Self.isWatched(instance.id, settings: settings, automations: automations) {
            var watch = watches[instance.id] ?? InstanceWatch()
            guard watch.isDue, let client = store.client(for: instance) else { continue }
            let notices = await watch.check(client: client, instanceID: instance.id)
            guard !Task.isCancelled, Self.isWatched(instance.id, settings: settings, automations: automations)
            else { return }
            watches[instance.id] = watch
            for notice in notices where settings.isOn(notice.event, for: instance.id) {
                poster.post(notice, instanceName: instance.name, canExplain: FailureAnalyst.isReady)
            }
            await automations.handle(notices, instance: instance)
        }
    }
}

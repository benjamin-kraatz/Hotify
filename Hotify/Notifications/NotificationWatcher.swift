import CoolifyAPI
import Foundation

/// Looks at every instance whose notifications are on, every 30 seconds while Hotify runs, and posts what changed.
/// It only runs while Hotify does, so on the Mac the menu bar companion keeps it going after the windows close.
final class NotificationWatcher {
    private let poster = NotificationPoster()
    private var watches: [UUID: InstanceWatch] = [:]
    private var task: Task<Void, Never>?

    func start(store: InstanceStore, settings: NotificationSettings) {
        task?.cancel()
        poster.registerCategories()
        task = Task { [weak self] in
            await settings.refreshAuthorization()
            while !Task.isCancelled {
                await self?.checkAll(store: store, settings: settings)
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }

    private func checkAll(store: InstanceStore, settings: NotificationSettings) async {
        // An instance turned off starts from a fresh baseline when it's turned on again.
        watches = watches.filter { settings.isEnabled($0.key) }
        for instance in store.instances where settings.isEnabled(instance.id) {
            var watch = watches[instance.id] ?? InstanceWatch()
            guard watch.isDue, let client = store.client(for: instance) else { continue }
            let notices = await watch.check(client: client, instanceID: instance.id)
            guard !Task.isCancelled, settings.isEnabled(instance.id) else { return }
            watches[instance.id] = watch
            for notice in notices where settings.isOn(notice.event, for: instance.id) {
                poster.post(notice, instanceName: instance.name, canExplain: FailureAnalyst.isReady)
            }
        }
    }
}

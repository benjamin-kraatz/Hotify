import CoolifyAPI
import Foundation

/// The App Group the app shares with its widgets. It holds instance names and URLs and what the widgets last saw,
/// never a token.
enum AppGroup {
    static let identifier = "group.sebastiankraatz.apps"

    /// The group is shared with other apps, so every key here starts with `hotify.`.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    private static let instancesKey = "hotify.instances"

    /// The saved instances, as the app last wrote them.
    static func instances() -> [CoolifyInstance] {
        guard let data = defaults.data(forKey: instancesKey) else { return [] }
        return (try? JSONDecoder().decode([CoolifyInstance].self, from: data)) ?? []
    }

    static func saveInstances(_ instances: [CoolifyInstance]) {
        guard let data = try? JSONEncoder().encode(instances) else { return }
        defaults.set(data, forKey: instancesKey)
    }
}

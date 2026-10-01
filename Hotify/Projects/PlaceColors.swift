import Foundation
import Observation

/// Whether a color belongs to a project or to an environment.
enum PlaceKind: String, Hashable, Sendable {
    case project
    case environment
}

/// The colors given to projects and environments, on every instance. Saved on this device and synced through
/// iCloud, one key per color, so two devices that color different projects do not undo each other.
@MainActor
@Observable
final class PlaceColors {
    /// Raw tints by `instance.kind.uuid`. A cleared color stays as `cleared`, so the clearing syncs too.
    private var entries: [String: String]

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let cloud: NSUbiquitousKeyValueStore?
    @ObservationIgnored private var observer: NSObjectProtocol?

    private static let localKey = "hotify.placeColors.v1"
    private static let cloudPrefix = "hotify.placeColor.v1."
    private static let cleared = "none"

    /// Pass `nil` for both to keep the colors in memory only, as previews and fixture instances do.
    init(defaults: UserDefaults? = .standard, cloud: NSUbiquitousKeyValueStore? = .default) {
        self.defaults = defaults
        self.cloud = cloud
        entries = defaults?.dictionary(forKey: Self.localKey) as? [String: String] ?? [:]
        guard let cloud else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { [weak self] notification in
            let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            // A full store is not a remote edit. The colors stay saved on this device.
            guard reason != NSUbiquitousKeyValueStoreQuotaViolationChange else { return }
            Task { @MainActor [weak self] in
                self?.pull()
            }
        }
        cloud.synchronize()
        pull()
        // Colors picked while iCloud was off reach it now.
        for (key, value) in entries where cloud.string(forKey: Self.cloudPrefix + key) == nil {
            cloud.set(value, forKey: Self.cloudPrefix + key)
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func tint(of kind: PlaceKind, _ uuid: String, in instanceID: UUID) -> PlaceTint? {
        entries[Self.key(kind, uuid, instanceID)].flatMap(PlaceTint.init(rawValue:))
    }

    func setTint(_ tint: PlaceTint?, of kind: PlaceKind, _ uuid: String, in instanceID: UUID) {
        let key = Self.key(kind, uuid, instanceID)
        guard tint != nil || entries[key] != nil else { return }
        let value = tint?.rawValue ?? Self.cleared
        guard entries[key] != value else { return }
        entries[key] = value
        defaults?.set(entries, forKey: Self.localKey)
        cloud?.set(value, forKey: Self.cloudPrefix + key)
    }

    /// Takes every color iCloud holds. The store keeps the newest write per key, which is the one to show.
    private func pull() {
        guard let cloud else { return }
        var merged = entries
        for (key, value) in cloud.dictionaryRepresentation where key.hasPrefix(Self.cloudPrefix) {
            guard let value = value as? String else { continue }
            merged[String(key.dropFirst(Self.cloudPrefix.count))] = value
        }
        guard merged != entries else { return }
        entries = merged
        defaults?.set(entries, forKey: Self.localKey)
    }

    private static func key(_ kind: PlaceKind, _ uuid: String, _ instanceID: UUID) -> String {
        "\(instanceID.uuidString).\(kind.rawValue).\(uuid)"
    }
}

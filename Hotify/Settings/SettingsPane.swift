import SwiftUI

/// One page of Settings. The Mac shows them as toolbar tabs, and iPhone and iPad push each one from a list.
enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case menuBar
    case notifications
    case automations
    case terminal
    case privacy
    case backupStorage
    case about

    var id: Self { self }

    /// The panes this device has. The menu bar and notifications are the Mac's, since only it keeps watching.
    static var available: [Self] {
        #if os(macOS)
        allCases
        #else
        [.automations, .terminal, .privacy, .backupStorage, .about]
        #endif
    }

    var title: String {
        switch self {
        case .menuBar: "Menu Bar"
        case .notifications: "Notifications"
        case .automations: "Automations"
        case .terminal: "Terminal"
        case .privacy: "Privacy"
        case .backupStorage: "Backup Storage"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .menuBar: "menubar.rectangle"
        case .notifications: "bell.badge"
        case .automations: "square.2.layers.3d"
        case .terminal: "terminal"
        case .privacy: "lock.shield"
        case .backupStorage: "externaldrive.connected.to.line.below"
        case .about: "flame"
        }
    }
}

import SwiftUI

/// Hotify's settings. On the Mac a window with one toolbar tab per pane, and on iPhone and iPad a sheet that lists
/// the panes and pushes each one.
struct SettingsView: View {
    var body: some View {
        #if os(macOS)
        TabView {
            ForEach(SettingsPane.available) { pane in
                Tab(pane.title, systemImage: pane.systemImage) {
                    SettingsPaneView(pane: pane)
                }
            }
        }
        // One width for every tab, so switching only changes the height. The scene's resizability follows this.
        .frame(width: 600)
        .frame(minHeight: 420, idealHeight: 620)
        #else
        List {
            ForEach(SettingsPane.available) { pane in
                NavigationLink(value: pane) {
                    Label {
                        Text(pane.title)
                    } icon: {
                        Image(systemName: pane.systemImage)
                            .foregroundStyle(.ember)
                    }
                }
            }
        }
        .navigationDestination(for: SettingsPane.self) { pane in
            SettingsPaneView(pane: pane)
        }
        #endif
    }
}

/// The content of one pane: a grouped form of its sections, or the About screen.
private struct SettingsPaneView: View {
    var pane: SettingsPane

    var body: some View {
        Group {
            switch pane {
            case .menuBar:
                #if os(macOS)
                form { MenuBarSettings() }
                #else
                EmptyView()
                #endif
            case .notifications:
                #if os(macOS)
                NotificationSettingsPane()
                #else
                EmptyView()
                #endif
            case .automations:
                form { AutomationsSection() }
            case .terminal:
                form { TerminalSettingsSection() }
            case .privacy:
                form { VariableLockSettings() }
            case .backupStorage:
                form { BackupStorageSection() }
            case .about:
                AboutView(buildInfo: .current)
            }
        }
        .navigationTitle(pane.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func form<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Form(content: content)
            .formStyle(.grouped)
    }
}

#Preview("On") {
    SettingsView()
        .environment(MenuBarModel(preview: true))
        .environment(NotificationSettings(defaults: nil))
        .environment(InstanceStore(instances: []))
        .environment(AutomationStore(defaults: nil))
        .environment(VariableLock(isRequired: true))
}

#Preview("Off") {
    SettingsView()
        .environment(MenuBarModel(preview: true))
        .environment(NotificationSettings(defaults: nil))
        .environment(InstanceStore(instances: []))
        .environment(AutomationStore(defaults: nil))
        .environment(VariableLock(isRequired: false))
}

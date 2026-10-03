import CoolifyAPI
import SwiftUI
import UserNotifications

/// The Notifications part of Settings: a switch per instance, and under each one that's on, a switch per event.
struct NotificationSettingsSection: View {
    @SwiftUI.Environment(NotificationSettings.self) private var settings
    @SwiftUI.Environment(InstanceStore.self) private var store

    var body: some View {
        Section {
            if store.instances.isEmpty {
                Text("Add an instance to get notified about it.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.instances) { instance in
                Toggle(
                    isOn: Binding(
                        get: { settings.isEnabled(instance.id) },
                        set: { isOn in Task { await settings.setEnabled(isOn, for: instance.id) } }
                    )
                ) {
                    Label {
                        Text(instance.name)
                        Text(instance.baseURL.host() ?? instance.baseURL.absoluteString)
                    } icon: {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(.ember)
                    }
                }
                if settings.isEnabled(instance.id) {
                    ForEach(NotificationEvent.allCases) { event in
                        Toggle(
                            isOn: Binding(
                                get: { settings.isChosen(event, for: instance.id) },
                                set: { settings.set(event, $0, for: instance.id) }
                            )
                        ) {
                            Text(event.title)
                            Text(event.detail)
                        }
                        .padding(.leading, 28)
                    }
                }
            }
            if settings.authorization == .denied, !settings.enabledInstances.isEmpty {
                Label(
                    "Notifications for Hotify are off in System Settings, so nothing shows.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.glow)
                #if os(macOS)
                Button("Open Notification Settings") {
                    if let url = URL(
                        string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
                    {
                        NSWorkspace.shared.open(url)
                    }
                }
                #endif
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text(
                "Hotify checks every 30 seconds while it runs. Show in Menu Bar keeps it running after you close its windows."
            )
        }
        .task { await settings.refreshAuthorization() }
        .animation(.snappy, value: settings.enabledInstances)
    }
}

#Preview {
    Form {
        NotificationSettingsSection()
    }
    .formStyle(.grouped)
    .environment(NotificationSettings(defaults: nil))
    .environment(InstanceStore(instances: []))
    .frame(width: 500, height: 300)
}

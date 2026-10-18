import CoolifyAPI
import SwiftUI
import UserNotifications

/// The Notifications pane: one section per instance, with its switch first and, once it's on, a switch per event.
struct NotificationSettingsPane: View {
    @SwiftUI.Environment(NotificationSettings.self) private var settings
    @SwiftUI.Environment(InstanceStore.self) private var store

    var body: some View {
        Form {
            sections
        }
        .formStyle(.grouped)
        .task { await settings.refreshAuthorization() }
        .animation(.snappy, value: settings.enabledInstances)
    }

    @ViewBuilder
    private var sections: some View {
        if settings.authorization == .denied, !settings.enabledInstances.isEmpty {
            Section {
                Label(
                    "Notifications for Hotify are off in System Settings, so nothing shows.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.glow)
                #if os(macOS)
                Button("Open Notification Settings", systemImage: "arrow.up.forward.app") {
                    if let url = URL(
                        string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
                    {
                        NSWorkspace.shared.open(url)
                    }
                }
                #endif
            }
        }
        if store.instances.isEmpty {
            Section {
                Text("Add an instance to get notified about it.")
                    .foregroundStyle(.secondary)
            } footer: {
                Text(schedule)
            }
        }
        ForEach(Array(store.instances.enumerated()), id: \.element.id) { index, instance in
            let isOn = settings.isEnabled(instance.id)
            Section {
                Toggle(
                    isOn: Binding(
                        get: { isOn },
                        set: { isOn in Task { await settings.setEnabled(isOn, for: instance.id) } }
                    )
                ) {
                    Label {
                        Text("Notify me about \(instance.name)")
                        Text(instance.baseURL.host() ?? instance.baseURL.absoluteString)
                    } icon: {
                        Image(systemName: isOn ? "bell.badge.fill" : "bell.slash")
                            .foregroundStyle(isOn ? Color.ember : Color.secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                if isOn {
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
            } header: {
                Text(instance.name)
            } footer: {
                if index == store.instances.count - 1 {
                    Text(schedule)
                }
            }
        }
    }

    private var schedule: String {
        "Hotify checks every 30 seconds while it runs. Show in Menu Bar keeps it running after you close its windows."
    }
}

#Preview {
    let instances = [
        CoolifyInstance(name: "Production", baseURL: URL(string: "https://coolify.example.com")!),
        CoolifyInstance(name: "Home lab", baseURL: URL(string: "http://10.0.0.4:8000")!),
    ]
    NotificationSettingsPane()
        .environment(NotificationSettings(defaults: nil))
        .environment(InstanceStore(instances: instances))
        .frame(width: 560, height: 520)
}

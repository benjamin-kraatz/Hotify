import SwiftUI

/// Hotify's settings. The Settings window on the Mac, and a sheet from the instance list on iPhone and iPad.
struct SettingsView: View {
    @SwiftUI.Environment(VariableLock.self) private var lock
    #if os(macOS)
    @SwiftUI.Environment(MenuBarModel.self) private var menuBar
    #endif

    private var lockMinutes: Int {
        Int(VariableLock.unlockDuration.components.seconds / 60)
    }

    var body: some View {
        Form {
            #if os(macOS)
            MenuBarSettings()
            NotificationSettingsSection()
            #endif
            Section {
                Toggle(
                    isOn: Binding(
                        get: { lock.isRequired },
                        set: { required in Task { await lock.setRequired(required) } }
                    )
                ) {
                    Label {
                        Text("Require \(lock.method.titleWithFallback)")
                        Text("Environment variable values stay hidden until you confirm it’s you.")
                    } icon: {
                        Image(systemName: lock.method.systemImage)
                            .foregroundStyle(.ember)
                    }
                }
                .disabled(lock.isAuthenticating)

                if lock.isRequired {
                    LabeledContent("Locks again") {
                        Text("After \(lockMinutes) minutes, or when you leave Hotify")
                    }
                    if lock.unlockedUntil != nil {
                        Button("Lock Values Now", systemImage: "lock.fill") {
                            lock.lock()
                        }
                    }
                }

                if let failure = lock.failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.glow)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Environment Variables")
            } footer: {
                Text(footer)
            }
            #if os(iOS)
            Section {
                NavigationLink {
                    AboutView(buildInfo: .current)
                } label: {
                    Label("About Hotify", systemImage: "info.circle")
                }
            }
            #endif
        }
        .formStyle(.grouped)
        .animation(.snappy, value: lock.isRequired)
        .animation(.snappy, value: lock.unlockedUntil)
        .animation(.snappy, value: lock.failure)
        #if os(macOS)
        .animation(.snappy, value: menuBar.enabled)
        .animation(.snappy, value: menuBar.watched)
        #endif
        #if os(macOS)
        .frame(width: 500)
        .frame(minHeight: 340, idealHeight: 640)
        #endif
    }

    private var footer: String {
        if lock.method == .unavailable {
            return "This \(UnlockMethod.deviceName) has no \(UnlockMethod.secretName), so nothing can confirm it’s you."
        }
        return lock.isRequired
            ? "Turning this off asks for \(lock.method.titleWithFallback) first."
            : "Anyone who can open Hotify on this \(UnlockMethod.deviceName) sees the values."
    }
}

#Preview("On") {
    SettingsView()
        .environment(MenuBarModel(preview: true))
        .environment(NotificationSettings(defaults: nil))
        .environment(InstanceStore(instances: []))
        .environment(VariableLock(isRequired: true))
}

#Preview("Off") {
    SettingsView()
        .environment(MenuBarModel(preview: true))
        .environment(NotificationSettings(defaults: nil))
        .environment(InstanceStore(instances: []))
        .environment(VariableLock(isRequired: false))
}

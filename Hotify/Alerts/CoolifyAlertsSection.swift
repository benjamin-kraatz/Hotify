import CoolifyAPI
import SwiftUI

/// The alerts Coolify sends for the selected instance's team: which channels are on, and a way into each one.
///
/// Coolify delivers these from the instance itself, so they arrive while Hotify is closed. They are not this
/// device's notifications, which the Notifications pane sets up.
struct CoolifyAlertsSection: View {
    /// When set, the section shows these values and does not touch the network or the Keychain.
    var previewInstance: CoolifyInstance?

    @SwiftUI.Environment(InstanceStore.self) private var store
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: CoolifyAlertsModel
    @State private var editing: AlertEditorTarget?

    init() {
        previewInstance = nil
        _model = State(initialValue: CoolifyAlertsModel())
    }

    /// A preview with fixed channels for `instance`.
    init(previewInstance: CoolifyInstance, model: CoolifyAlertsModel) {
        self.previewInstance = previewInstance
        _model = State(initialValue: model)
    }

    private var instance: CoolifyInstance? { previewInstance ?? store.selected }

    var body: some View {
        Group {
            if let message = statusMessage {
                Section {
                    Text(message)
                        .foregroundStyle(.secondary)
                } footer: {
                    Text(explanation)
                }
            } else if let instance {
                Section {
                    placeRow(instance)
                } footer: {
                    Text(explanation)
                }
                channelsSection(instance)
            }
        }
        .task(id: store.selected?.id) {
            guard previewInstance == nil, store.selected != nil else { return }
            await reload()
        }
        .sheet(item: $editing) { target in
            AlertChannelEditor(settings: target.settings, instanceName: target.instanceName) { update in
                try await save(update, to: target.instanceID)
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: model.notice)
        .animation(reduceMotion ? nil : .snappy, value: model.hasLoaded)
    }

    private var statusMessage: String? {
        if previewInstance != nil { return nil }
        if store.instances.isEmpty { return "Add an instance to set up the alerts Coolify sends." }
        if store.selected == nil { return "Select an instance to set up the alerts Coolify sends." }
        return nil
    }

    private var explanation: String {
        #if os(macOS)
        "Coolify sends these alerts itself, so they keep coming while Hotify is closed. They reach everyone the team sets up, not only this Mac. Hotify’s own notifications are under Notifications."
        #else
        "Coolify sends these alerts itself, so they keep coming while Hotify is closed. They reach everyone the team sets up, not only this device."
        #endif
    }

    private func placeRow(_ instance: CoolifyInstance) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.ember)
                .frame(width: 32, height: 32)
                .background(.ember.opacity(0.12), in: .rect(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(instance.name)
                    .fontWeight(.semibold)
                Text(placeDetail(instance))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if previewInstance == nil {
                Button("Reload", systemImage: "arrow.clockwise") {
                    Task { await reload() }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Read the alert settings from Coolify again")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func placeDetail(_ instance: CoolifyInstance) -> String {
        let host = instance.baseURL.host() ?? instance.baseURL.absoluteString
        guard let team = model.teamName, !team.isEmpty else { return host }
        return "Team \(team) · \(host)"
    }

    @ViewBuilder
    private func channelsSection(_ instance: CoolifyInstance) -> some View {
        Section {
            if let unavailable = model.unavailable {
                Label(unavailable, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.glow)
                    .textSelection(.enabled)
            } else if !model.hasLoaded {
                Kindling(caption: "Reading alert settings…", height: 22)
                    .frame(height: 90)
            } else {
                if let notice = model.notice {
                    Label(notice, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.ember)
                        .symbolEffect(.bounce, value: notice)
                }
                ForEach(NotificationChannel.allCases) { channel in
                    channelRow(channel, instance: instance)
                }
            }
        } header: {
            Text("Channels")
        }
    }

    private func channelRow(_ channel: NotificationChannel, instance: CoolifyInstance) -> some View {
        let settings = model.channels[channel]
        let failure = model.failures[channel]
        return Button {
            guard let settings, let instanceID = model.instanceID else { return }
            editing = AlertEditorTarget(settings: settings, instanceID: instanceID, instanceName: instance.name)
        } label: {
            HStack(spacing: 12) {
                AlertChannelIcon(channel: channel, isOn: settings?.isEnabled == true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.title)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(status(settings, failure: failure))
                        .font(.caption)
                        .foregroundStyle(failure == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.glow))
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if settings != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(settings == nil)
        .accessibilityElement(children: .combine)
        .accessibilityHint(settings == nil ? "" : "Opens its alert settings")
    }

    private func status(_ settings: NotificationChannelSettings?, failure: String?) -> String {
        if let failure { return failure }
        guard let settings else { return "Not read yet" }
        guard settings.isEnabled else { return "Off" }
        let count = settings.subscribedEvents.count
        let events = count == 0 ? "no events chosen" : count == 1 ? "1 event" : "\(count) events"
        if settings.channel == .email {
            let draft = AlertChannelDraft(settings: settings)
            return "On · \(draft.emailTransport.title) · \(events)"
        }
        return "On · \(events)"
    }

    private func reload() async {
        guard let instance = store.selected else { return }
        do {
            let client = try connectedClient(instance.id)
            await model.load(client, instanceID: instance.id)
        } catch is CancellationError {
            return
        } catch {
            model.unavailable = AlertFailure.loading(error)
            model.hasLoaded = true
        }
    }

    private func save(_ update: NotificationChannelUpdate, to instanceID: UUID) async throws {
        if previewInstance != nil {
            var values = model.channels[update.channel]?.values ?? [:]
            for (key, value) in update.changes { values[key] = value }
            model.apply(NotificationChannelSettings(channel: update.channel, values: values), instanceID: instanceID)
            return
        }
        let client = try connectedClient(instanceID)
        let saved = try await client.updateNotificationSettings(update)
        model.apply(saved, instanceID: instanceID)
    }

    /// The client for one instance. A missing token is reported without logging it.
    private func connectedClient(_ instanceID: UUID) throws -> CoolifyClient {
        guard let instance = store.instances.first(where: { $0.id == instanceID }) else {
            throw CoolifyError(message: "That instance is no longer in Hotify.")
        }
        #if DEBUG
        if let fixture = store.fixtureClients[instance.id] {
            return fixture
        }
        #endif
        guard let token = TokenStore.load(for: instance.id), !token.isEmpty else {
            throw CoolifyError(message: "\(instance.name) has no API token on this device.")
        }
        return try CoolifyClient(instanceURL: instance.baseURL, token: token)
    }
}

/// The channel an editor sheet is open for, pinned to the instance it was opened on.
private struct AlertEditorTarget: Identifiable {
    var settings: NotificationChannelSettings
    var instanceID: UUID
    var instanceName: String
    var id: NotificationChannel { settings.channel }
}

#Preview("Channels") {
    let instance = CoolifyInstance(name: "Production", baseURL: URL(string: "https://coolify.example.com")!)
    Form {
        CoolifyAlertsSection(
            previewInstance: instance,
            model: CoolifyAlertsModel(
                preview: [
                    NotificationChannelSettings(
                        channel: .email,
                        values: [
                            "smtp_enabled": .bool(true), "resend_enabled": .bool(false),
                            "use_instance_email_settings": .bool(false),
                            "deployment_failure_email_notifications": .bool(true),
                            "backup_failure_email_notifications": .bool(true),
                        ]
                    ),
                    NotificationChannelSettings(
                        channel: .discord,
                        values: [
                            "discord_enabled": .bool(true), "discord_ping_enabled": .bool(false),
                            "deployment_failure_discord_notifications": .bool(true),
                        ]
                    ),
                    NotificationChannelSettings(channel: .slack, values: ["slack_enabled": .bool(false)]),
                    NotificationChannelSettings(channel: .pushover, values: ["pushover_enabled": .bool(false)]),
                    NotificationChannelSettings(channel: .webhook, values: ["webhook_enabled": .bool(false)]),
                ],
                instanceID: instance.id,
                teamName: "Root Team",
                failures: [.telegram: "Coolify didn’t let this token read alert settings."]
            )
        )
    }
    .formStyle(.grouped)
    .environment(InstanceStore(instances: [instance]))
    .frame(width: 560, height: 560)
}

#Preview("No instance") {
    Form {
        CoolifyAlertsSection()
    }
    .formStyle(.grouped)
    .environment(InstanceStore(instances: []))
    .frame(width: 560, height: 240)
}

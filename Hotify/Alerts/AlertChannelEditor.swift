import CoolifyAPI
import SwiftUI

/// Edits one of the team's Coolify alert channels: whether it is on, where it sends, and which events it carries.
///
/// Edits stay in memory until Save, which sends only what changed. A failed save keeps every edit and says why.
struct AlertChannelEditor: View {
    var instanceName: String
    var onSave: (NotificationChannelUpdate) async throws -> Void

    @SwiftUI.Environment(\.dismiss) private var dismiss
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: AlertChannelDraft
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var fieldErrors: [String: String] = [:]
    @State private var isConfirmingDiscard = false

    init(
        settings: NotificationChannelSettings,
        instanceName: String,
        onSave: @escaping (NotificationChannelUpdate) async throws -> Void
    ) {
        self.instanceName = instanceName
        self.onSave = onSave
        _draft = State(initialValue: AlertChannelDraft(settings: settings))
    }

    private var channel: NotificationChannel { draft.channel }
    private var problems: [String: String] { draft.problems }
    private var canSave: Bool { draft.hasChanges && problems.isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                switchSection
                if channel.fields.contains(where: \.isHidden), !draft.settings.revealsSensitiveValues {
                    Section {
                        Label(
                            "This token can’t read the addresses and keys Coolify saved. Blank fields keep them.",
                            systemImage: "eye.slash"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
                destinationSections
                eventSections
                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.glow)
                            .textSelection(.enabled)
                        if let other = fieldErrors[""] {
                            Text(other)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(channel.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
            .onChange(of: draft) { _, _ in
                saveError = nil
                fieldErrors = [:]
            }
            .confirmationDialog(
                "Discard your changes to \(channel.title)?",
                isPresented: $isConfirmingDiscard,
                titleVisibility: .visible
            ) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .animation(reduceMotion ? nil : .snappy, value: draft.isEnabled)
            .animation(reduceMotion ? nil : .snappy, value: draft.emailTransport)
            .animation(reduceMotion ? nil : .snappy, value: saveError)
        }
        .interactiveDismissDisabled(draft.hasChanges)
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 560, idealHeight: 680)
        #endif
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", role: .cancel) {
                if draft.hasChanges {
                    isConfirmingDiscard = true
                } else {
                    dismiss()
                }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Save") {
                    Task { await save() }
                }
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Sections

    private var switchSection: some View {
        Section {
            HStack(spacing: 12) {
                AlertChannelIcon(channel: channel, isOn: draft.isEnabled)
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.title)
                        .font(.headline)
                    Text("Sent by Coolify on \(instanceName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if channel == .email {
                Picker("Send with", selection: $draft.emailTransport) {
                    ForEach(draft.emailTransports) { transport in
                        Text(transport.title).tag(transport)
                    }
                }
            } else {
                Toggle(isOn: Binding(get: { draft.isEnabled }, set: { draft.setEnabled($0) })) {
                    Text("Send alerts to \(channel.title)")
                    Text(channel.destination)
                }
            }
        } footer: {
            if channel == .email {
                Text(emailFooter)
            }
        }
    }

    private var emailFooter: String {
        switch draft.emailTransport {
        case .off: "Coolify sends no alert email for this team."
        case .instance:
            "Uses the mail server in Coolify’s instance settings. Only an instance admin can change that server."
        case .smtp: "Coolify sends through your own mail server."
        case .resend: "Coolify sends through your Resend account."
        }
    }

    @ViewBuilder
    private var destinationSections: some View {
        switch channel {
        case .email:
            if draft.emailTransport != .off {
                fieldSection(["smtp_recipients"], footer: "Separate addresses with commas.")
            }
            if draft.emailTransport == .smtp || draft.emailTransport == .resend {
                fieldSection(["smtp_from_address", "smtp_from_name"], header: "Sender")
            }
            if draft.emailTransport == .smtp {
                fieldSection(
                    [
                        "smtp_host", "smtp_port", "smtp_encryption", "smtp_username", "smtp_password",
                        "smtp_timeout", "smtp_ehlo_domain",
                    ],
                    header: "Mail Server"
                )
            }
            if draft.emailTransport == .resend {
                fieldSection(["resend_api_key"], header: "Resend")
            }
        case .discord:
            Section {
                fieldRows(["discord_webhook_url"])
                if draft.toggles["discord_ping_enabled"] != nil {
                    Toggle(isOn: toggle("discord_ping_enabled")) {
                        Text("Mention @here")
                        Text("Pings everyone in the channel who is online.")
                    }
                }
            } header: {
                Text("Destination")
            } footer: {
                Text("Copy the address from the channel’s Integrations › Webhooks in Discord.")
            }
        case .slack:
            fieldSection(
                ["slack_webhook_url"], header: "Destination",
                footer: "Create an incoming webhook in your Slack app and paste its address.")
        case .telegram:
            fieldSection(
                ["telegram_token", "telegram_chat_id"], header: "Destination",
                footer: "Add the bot to the chat first. A group’s chat ID starts with -100.")
        case .pushover:
            fieldSection(
                ["pushover_user_key", "pushover_api_token"], header: "Destination",
                footer: "The API token belongs to an application you create in Pushover.")
        case .webhook:
            fieldSection(
                ["webhook_url"], header: "Destination",
                footer: "Coolify refuses addresses on private networks unless the instance allows them.")
        }
    }

    private var eventSections: some View {
        ForEach(AlertEventGroup.allCases) { group in
            let events = group.events.filter { draft.toggles[channel.eventKey($0)] != nil }
            if !events.isEmpty {
                Section {
                    ForEach(events) { event in
                        Toggle(event.title, isOn: toggle(channel.eventKey(event)))
                        if let thread = channel.threadKey(event), draft.isOn(channel.eventKey(event)),
                            draft.texts[thread] != nil
                        {
                            fieldRows([thread])
                                .padding(.leading, 20)
                        }
                    }
                } header: {
                    Text(group.title)
                } footer: {
                    if group == .servers, channel == .telegram {
                        Text("A topic ID posts that event to one thread of a forum chat.")
                    }
                }
            }
        }
    }

    // MARK: Fields

    private func fieldSection(_ keys: [String], header: String? = nil, footer: String? = nil) -> some View {
        Section {
            fieldRows(keys)
        } header: {
            if let header { Text(header) }
        } footer: {
            if let footer { Text(footer) }
        }
    }

    @ViewBuilder
    private func fieldRows(_ keys: [String]) -> some View {
        ForEach(keys.compactMap { draft.channel.field($0) }.filter { draft.settings.offers($0) }) { field in
            fieldRow(field)
        }
    }

    @ViewBuilder
    private func fieldRow(_ field: NotificationSettingField) -> some View {
        let label = AlertFieldLabel(field.key)
        let problem = fieldErrors[field.key] ?? (draft.hasChanges ? problems[field.key] : nil)
        if field.isCredential {
            AlertSecretField(
                title: label.title,
                example: label.prompt,
                stored: draft.storedCredential(field.key),
                isWithheld: draft.isWithheld(field.key),
                text: credential(field.key),
                isRemoved: removed(field.key),
                problem: problem
            )
        } else if case .choice(let options) = field.kind {
            VStack(alignment: .leading, spacing: 4) {
                Picker(label.title, selection: text(field.key)) {
                    if (draft.texts[field.key] ?? "").isEmpty {
                        Text("Not set").tag("")
                    }
                    ForEach(options, id: \.self) { option in
                        Text(AlertFieldLabel.encryptionTitle(option)).tag(option)
                    }
                }
                problemText(problem)
            }
        } else {
            AlertTextFieldRow(
                field: field,
                label: label,
                isWithheld: draft.isWithheld(field.key),
                text: text(field.key),
                isRemoved: removed(field.key),
                problem: problem
            )
        }
    }

    @ViewBuilder
    private func problemText(_ problem: String?) -> some View {
        if let problem {
            Text(problem)
                .font(.caption)
                .foregroundStyle(.glow)
        }
    }

    private func toggle(_ key: String) -> Binding<Bool> {
        Binding(get: { draft.isOn(key) }, set: { draft.toggles[key] = $0 })
    }

    private func text(_ key: String) -> Binding<String> {
        Binding(get: { draft.texts[key] ?? "" }, set: { draft.texts[key] = $0 })
    }

    private func credential(_ key: String) -> Binding<String> {
        Binding(get: { draft.credentials[key] ?? "" }, set: { draft.credentials[key] = $0 })
    }

    private func removed(_ key: String) -> Binding<Bool> {
        Binding(
            get: { draft.cleared.contains(key) },
            set: { isRemoved in
                if isRemoved {
                    draft.cleared.insert(key)
                    draft.credentials[key] = nil
                    if draft.texts[key] != nil { draft.texts[key] = "" }
                } else {
                    draft.cleared.remove(key)
                }
            }
        )
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(draft.update)
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            fieldErrors = AlertFailure.fieldMessages(error, channel: channel)
            saveError = AlertFailure.saving(error, channel: channel)
        }
    }
}

/// A plain setting: text, an address, or a number. A withheld one starts blank, which keeps it, and can be removed.
private struct AlertTextFieldRow: View {
    var field: NotificationSettingField
    var label: AlertFieldLabel
    var isWithheld: Bool
    @Binding var text: String
    @Binding var isRemoved: Bool
    var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isRemoved {
                LabeledContent(label.title) {
                    HStack(spacing: 8) {
                        Text("Removed when you save")
                            .foregroundStyle(.secondary)
                        Button("Undo") { isRemoved = false }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    TextField(
                        label.title,
                        text: $text,
                        prompt: Text(isWithheld ? "Kept by Coolify. Type to replace it." : label.prompt)
                    )
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(field.key == "smtp_from_name" ? .words : .never)
                    .keyboardType(keyboard)
                    #endif
                    if isWithheld {
                        Button("Remove \(label.title)", systemImage: "trash") {
                            isRemoved = true
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Remove the saved value when you save")
                    }
                }
            }
            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.glow)
            }
        }
    }

    #if os(iOS)
    private var keyboard: UIKeyboardType {
        switch field.kind {
        case .email: .emailAddress
        case .url, .hostname: .URL
        case .integer: .numberPad
        default: field.key == "smtp_recipients" ? .emailAddress : .default
        }
    }
    #endif
}

#Preview("Discord, shared") {
    AlertChannelEditor(
        settings: NotificationChannelSettings(
            channel: .discord,
            values: [
                "discord_enabled": .bool(true),
                "discord_webhook_url": .text("https://discord.com/api/webhooks/1/preview"),
                "discord_ping_enabled": .bool(false),
                "deployment_failure_discord_notifications": .bool(true),
                "deployment_success_discord_notifications": .bool(false),
                "backup_failure_discord_notifications": .bool(true),
                "server_unreachable_discord_notifications": .bool(true),
                "server_reachable_discord_notifications": .bool(false),
            ]
        ),
        instanceName: "Production",
        onSave: { _ in }
    )
}

#Preview("Email, withheld") {
    AlertChannelEditor(
        settings: NotificationChannelSettings(
            channel: .email,
            values: [
                "smtp_enabled": .bool(true),
                "resend_enabled": .bool(false),
                "use_instance_email_settings": .bool(false),
                "smtp_port": .integer(587),
                "smtp_encryption": .text("starttls"),
                "smtp_timeout": .null,
                "smtp_ehlo_domain": .null,
                "deployment_failure_email_notifications": .bool(true),
                "backup_failure_email_notifications": .bool(true),
            ]
        ),
        instanceName: "Home lab",
        onSave: { _ in throw CoolifyError(statusCode: 403, message: "Missing required permissions: write") }
    )
}

#Preview("Telegram") {
    AlertChannelEditor(
        settings: NotificationChannelSettings(
            channel: .telegram,
            values: [
                "telegram_enabled": .bool(false),
                "telegram_token": .null,
                "telegram_chat_id": .null,
                "deployment_failure_telegram_notifications": .bool(true),
                "telegram_notifications_deployment_failure_thread_id": .null,
            ]
        ),
        instanceName: "Production",
        onSave: { _ in }
    )
}

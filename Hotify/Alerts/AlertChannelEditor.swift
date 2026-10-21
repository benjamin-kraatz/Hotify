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
    /// The way email last went out in this sheet, so turning it back on picks that up again.
    @State private var lastTransport: AlertChannelDraft.EmailTransport
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
        let draft = AlertChannelDraft(settings: settings)
        _draft = State(initialValue: draft)
        let transport = draft.emailTransport == .off ? draft.emailTransports.first { $0 != .off } : draft.emailTransport
        _lastTransport = State(initialValue: transport ?? .off)
    }

    private var channel: NotificationChannel { draft.channel }
    private var problems: [String: String] { draft.problems }
    private var canSave: Bool { draft.hasChanges && problems.isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let saveError {
                    NoticeBanner(message: [saveError, fieldErrors[""]].compactMap { $0 }.joined(separator: " "))
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }
                Form {
                    switchSection
                    destinationSections
                    eventSections
                }
                .formStyle(.grouped)
            }
            #if os(iOS)
            .background(Color(.systemGroupedBackground))
            #endif
            .navigationTitle(channel.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
            .onChange(of: draft) { _, _ in
                saveError = nil
                fieldErrors = [:]
            }
            .onChange(of: draft.emailTransport) { _, transport in
                if transport != .off { lastTransport = transport }
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
            .animation(reduceMotion ? nil : .snappy, value: draft.toggles)
            .animation(reduceMotion ? nil : .snappy, value: draft.cleared)
            .animation(reduceMotion ? nil : .snappy, value: saveError)
        }
        .interactiveDismissDisabled(draft.hasChanges)
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 540, minHeight: 560, idealHeight: 700)
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
                .help(saveHelp)
            }
        }
    }

    private var saveHelp: String {
        if !draft.hasChanges { return "Nothing has changed yet" }
        if !problems.isEmpty { return "Fix the marked fields first" }
        return "Send the changes to Coolify"
    }

    // MARK: The switch

    private var switchSection: some View {
        Section {
            Toggle(isOn: channel == .email ? emailIsOn : isEnabled) {
                HStack(spacing: 12) {
                    AlertChannelIcon(channel: channel, isOn: draft.isEnabled)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(channel == .email ? "Send alerts by email" : "Send alerts to \(channel.title)")
                        Text(channel.destination)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if channel == .email, draft.emailTransport != .off {
                Picker("Send with", selection: $draft.emailTransport) {
                    ForEach(draft.emailTransports.filter { $0 != .off }) { transport in
                        Text(transport.title).tag(transport)
                    }
                }
            }
        } footer: {
            Text(switchFooter)
        }
    }

    private var isEnabled: Binding<Bool> {
        Binding(get: { draft.isEnabled }, set: { draft.setEnabled($0) })
    }

    private var emailIsOn: Binding<Bool> {
        Binding(
            get: { draft.emailTransport != .off },
            set: { isOn in draft.emailTransport = isOn ? lastTransport : .off }
        )
    }

    private var switchFooter: String {
        var lines = ["Coolify on \(instanceName) sends these to the whole team."]
        if channel == .email {
            switch draft.emailTransport {
            case .off: break
            case .instance:
                lines.append(
                    "It uses the mail server in the instance settings, which only an instance admin can change.")
            case .smtp: lines.append("It sends through your own mail server.")
            case .resend: lines.append("It sends through your Resend account.")
            }
        }
        if !draft.settings.revealsSensitiveValues {
            lines.append(
                "This token can’t read the values Coolify saved, so those fields start blank. Blank keeps them.")
        }
        return lines.joined(separator: " ")
    }

    // MARK: Where it sends

    @ViewBuilder
    private var destinationSections: some View {
        switch channel {
        case .email:
            if draft.emailTransport != .off {
                fieldSection(["smtp_recipients"], header: "Recipients", footer: "Separate addresses with commas.")
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
                    header: "Mail Server",
                    footer: "Username, password, timeout, and EHLO domain can stay blank."
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

    // MARK: Events

    /// The groups with at least one event this Coolify version offers on the channel.
    private var eventGroups: [(group: AlertEventGroup, events: [NotificationChannelEvent])] {
        AlertEventGroup.allCases.compactMap { group in
            let events = group.events.filter { draft.toggles[channel.eventKey($0)] != nil }
            return events.isEmpty ? nil : (group, events)
        }
    }

    /// The first group that shows a topic field, which is where the field is explained.
    private var firstGroupWithTopic: AlertEventGroup? {
        eventGroups.first { _, events in events.contains { showsTopic($0) } }?.group
    }

    private var eventSections: some View {
        let groups = eventGroups
        return ForEach(groups, id: \.group) { group, events in
            Section {
                ForEach(events) { event in
                    Toggle(event.title, isOn: toggle(channel.eventKey(event)))
                    if showsTopic(event), let thread = channel.threadKey(event) {
                        fieldRows([thread])
                            .padding(.leading, 20)
                    }
                }
            } header: {
                if group == groups.first?.group {
                    HStack {
                        Text(group.title)
                        Spacer()
                        eventPicks
                    }
                } else {
                    Text(group.title)
                }
            } footer: {
                if group == firstGroupWithTopic {
                    Text("A topic ID posts the event to one topic of a forum chat. Blank posts to the main chat.")
                }
            }
        }
    }

    /// Flips every event the channel offers at once. Only the ones that change are sent.
    private var eventPicks: some View {
        Menu("Select") {
            Button("All Events") { pickEvents { _ in true } }
            Button("Problems Only") { pickEvents(\.isProblem) }
            Button("None") { pickEvents { _ in false } }
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .textCase(nil)
        .accessibilityLabel("Select events")
        .help("Turn every event on, keep the problems, or turn them all off")
    }

    private func pickEvents(_ isOn: (NotificationChannelEvent) -> Bool) {
        for event in NotificationChannelEvent.allCases where draft.toggles[channel.eventKey(event)] != nil {
            draft.toggles[channel.eventKey(event)] = isOn(event)
        }
    }

    private func showsTopic(_ event: NotificationChannelEvent) -> Bool {
        guard let thread = channel.threadKey(event), draft.texts[thread] != nil else { return false }
        return draft.isOn(channel.eventKey(event))
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
            Picker(selection: text(field.key)) {
                if (draft.texts[field.key] ?? "").isEmpty {
                    Text("Not set").tag("")
                }
                ForEach(options, id: \.self) { option in
                    Text(AlertFieldLabel.encryptionTitle(option)).tag(option)
                }
            } label: {
                Text(label.title)
                if let problem {
                    Text(problem)
                        .foregroundStyle(.glow)
                }
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

/// A plain setting: text, an address, or a number, with its label beside it, as iOS shows only the prompt of a
/// bare field. A withheld one starts blank, which keeps it, and can be removed. The recipients list takes the whole
/// row, since it grows past one line.
private struct AlertTextFieldRow: View {
    var field: NotificationSettingField
    var label: AlertFieldLabel
    var isWithheld: Bool
    @Binding var text: String
    @Binding var isRemoved: Bool
    var problem: String?

    private var isWide: Bool { field.key == "smtp_recipients" }

    var body: some View {
        if isWide {
            VStack(alignment: .leading, spacing: 4) {
                if isRemoved {
                    removedRow
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        TextField(label.title, text: $text, prompt: Text(verbatim: prompt), axis: .vertical)
                            .lineLimit(1...4)
                            .labelsHidden()
                            .autocorrectionDisabled()
                            #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                            #endif
                        removeButton
                    }
                }
                if let problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(.glow)
                }
            }
        } else {
            LabeledContent {
                if isRemoved {
                    removedRow
                } else {
                    HStack(spacing: 8) {
                        TextField(label.title, text: $text, prompt: Text(verbatim: prompt))
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            #if os(iOS)
                        .textInputAutocapitalization(field.key == "smtp_from_name" ? .words : .never)
                        .keyboardType(keyboard)
                            #endif
                        removeButton
                    }
                }
            } label: {
                Text(label.title)
                if let problem {
                    Text(problem)
                        .foregroundStyle(.glow)
                }
            }
        }
    }

    private var prompt: String {
        isWithheld ? "Kept by Coolify" : label.prompt
    }

    private var removedRow: some View {
        HStack(spacing: 8) {
            Text("Removed on save")
                .foregroundStyle(.secondary)
            Button("Undo") { isRemoved = false }
                .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var removeButton: some View {
        if isWithheld {
            Button("Remove \(label.title)", systemImage: "trash") {
                isRemoved = true
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Remove the saved value when you save")
        }
    }

    #if os(iOS)
    private var keyboard: UIKeyboardType {
        switch field.kind {
        case .email: return .emailAddress
        case .url, .hostname: return .URL
        case .integer: return .numberPad
        default: break
        }
        switch field.key {
        case "smtp_host": return .URL
        // A group's chat ID is a negative number, which the number pad can't type.
        case "telegram_chat_id": return .numbersAndPunctuation
        default: return field.key.hasPrefix("telegram_notifications_") ? .numberPad : .default
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
                "backup_failure_telegram_notifications": .bool(false),
                "telegram_notifications_backup_failure_thread_id": .null,
            ]
        ),
        instanceName: "Production",
        onSave: { _ in }
    )
}

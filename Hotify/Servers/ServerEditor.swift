import CoolifyAPI
import SwiftUI

/// Adds a server, or edits the connection and capacity of one Coolify already has.
///
/// A pasted private key is sent once and kept only in this sheet until that request finishes.
struct ServerEditor: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    var client: CoolifyClient?
    /// Set when this sheet edits a server. Nil adds one.
    var serverID: String?
    var onCreated: (String) -> Void = { _ in }
    var onDeleted: () -> Void = {}

    @State private var name: String
    @State private var details: String
    @State private var ip: String
    @State private var port: Int
    @State private var userName: String
    @State private var keySource: ServerKeySource
    @State private var selectedKeyUUID: String
    @State private var keyName: String
    @State private var keyText: String
    @State private var validateImmediately: Bool
    @State private var isBuildServer: Bool
    @State private var concurrentBuilds: String
    @State private var deploymentTimeout: String
    @State private var queueLimit: String
    @State private var diskThreshold: String
    @State private var diskFrequency: String
    @State private var connectionTimeout: String
    @State private var keys: [PrivateKeySummary]
    @State private var isLoading: Bool
    @State private var didSeed: Bool
    @State private var isSaving = false
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var confirmDelete = false

    init(
        client: CoolifyClient?,
        serverID: String? = nil,
        server: Server? = nil,
        keys: [PrivateKeySummary] = [],
        onCreated: @escaping (String) -> Void = { _ in },
        onDeleted: @escaping () -> Void = {}
    ) {
        self.client = client
        self.serverID = server?.uuid ?? serverID
        self.onCreated = onCreated
        self.onDeleted = onDeleted
        let values = ServerFormValues(server)
        let initialKey = values.privateKeyUUID.isEmpty ? (keys.first?.uuid ?? "") : values.privateKeyUUID
        _name = State(initialValue: values.name)
        _details = State(initialValue: values.details)
        _ip = State(initialValue: values.ip)
        _port = State(initialValue: values.port)
        _userName = State(initialValue: values.userName)
        _keySource = State(initialValue: initialKey.isEmpty && keys.isEmpty ? .pasted : .existing)
        _selectedKeyUUID = State(initialValue: initialKey)
        _keyName = State(initialValue: "")
        _keyText = State(initialValue: "")
        _validateImmediately = State(initialValue: true)
        _isBuildServer = State(initialValue: values.isBuildServer)
        _concurrentBuilds = State(initialValue: values.concurrentBuilds)
        _deploymentTimeout = State(initialValue: values.deploymentTimeout)
        _queueLimit = State(initialValue: values.queueLimit)
        _diskThreshold = State(initialValue: values.diskThreshold)
        _diskFrequency = State(initialValue: values.diskFrequency)
        _connectionTimeout = State(initialValue: values.connectionTimeout)
        _keys = State(initialValue: keys)
        _isLoading = State(initialValue: server == nil && serverID != nil && client != nil)
        _didSeed = State(initialValue: server != nil)
    }

    private var isEditing: Bool { serverID != nil }

    private var problem: String? {
        if trimmed(name).isEmpty { return "Enter a name." }
        if trimmed(ip).isEmpty { return "Enter an IP address." }
        if !(1...65_535).contains(port) { return "Port must be from 1 to 65535." }
        if trimmed(userName).isEmpty { return "Enter a user." }
        if let keyProblem { return keyProblem }
        if let message = check(concurrentBuilds, label: "Concurrent builds") { return message }
        if let message = check(deploymentTimeout, label: "Deployment timeout", range: 1...Int.max) { return message }
        if let message = check(queueLimit, label: "Queue limit") { return message }
        if let message = check(diskThreshold, label: "Disk threshold", range: 0...100) { return message }
        if let message = check(connectionTimeout, label: "Connection timeout", range: 1...300) { return message }
        return nil
    }

    /// Paste fields show when the user asks for a new key, and when the instance has none yet.
    private var usesPastedKey: Bool {
        keySource == .pasted || (keys.isEmpty && selectedKeyUUID.isEmpty)
    }

    private var keyProblem: String? {
        if usesPastedKey {
            return keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Paste a private key." : nil
        }
        return selectedKeyUUID.isEmpty ? "Choose a private key, or paste one." : nil
    }

    private var canSave: Bool {
        client != nil && problem == nil && !isSaving && !isLoading && (didSeed || !isEditing)
    }

    private var keyOptions: [PrivateKeySummary] {
        var options = keys
        if !selectedKeyUUID.isEmpty, !options.contains(where: { $0.uuid == selectedKeyUUID }) {
            options.append(PrivateKeySummary(uuid: selectedKeyUUID, name: "Current key"))
        }
        return options.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Changes that clear a save error. The pasted key stays out of this string.
    private var editToken: String {
        [
            name, details, ip, String(port), userName, keySource.rawValue, selectedKeyUUID, keyName,
            String(isBuildServer), String(validateImmediately), concurrentBuilds, deploymentTimeout, queueLimit,
            diskThreshold, diskFrequency, connectionTimeout,
        ].joined(separator: "\u{1e}")
    }

    var body: some View {
        NavigationStack {
            form
                .navigationTitle(isEditing ? "Edit Server" : "Add Server")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                            .disabled(isSaving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button(isEditing ? "Save" : "Add") {
                                Task { await save() }
                            }
                            .disabled(!canSave)
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                }
                .confirmationDialog(
                    "Delete \(trimmed(name).isEmpty ? "this server" : trimmed(name))?",
                    isPresented: $confirmDelete,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) { Task { await delete() } }
                } message: {
                    Text("Coolify deletes this server.")
                }
                .onChange(of: editToken) { _, _ in saveError = nil }
                .onChange(of: keyText) { _, _ in saveError = nil }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: isEditing ? 640 : 560)
        #endif
        .interactiveDismissDisabled(isSaving)
        .animation(reduceMotion ? nil : .snappy, value: saveError)
        .animation(reduceMotion ? nil : .snappy, value: isLoading)
        .animation(reduceMotion ? nil : .snappy, value: keySource)
        .task { await load() }
    }

    @ViewBuilder
    private var form: some View {
        if isLoading {
            ProgressView(isEditing ? "Loading server…" : "Loading keys…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isEditing, !didSeed {
            ContentUnavailableView {
                Label("Server unavailable", systemImage: "server.rack")
            } description: {
                Text(loadError ?? "Hotify is not connected to this instance.")
            } actions: {
                if client != nil {
                    Button("Try Again") { Task { await load() } }
                        .glassButton()
                }
            }
        } else {
            Form {
                connection
                keySection
                buildServer
                if !isEditing {
                    validate
                }
                if isEditing {
                    capacity
                    deleteSection
                }
                notices
            }
            .formStyle(.grouped)
        }
    }

    private var connection: some View {
        Section {
            TextField("Name", text: $name, prompt: Text("edge"))
            TextField("Description", text: $details, prompt: Text("Optional"))
            TextField("IP", text: $ip, prompt: Text(verbatim: "10.0.0.8"))
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.numbersAndPunctuation)
                #endif
            TextField("Port", value: $port, format: .number.grouping(.never))
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            TextField("User", text: $userName, prompt: Text("root"))
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        } header: {
            Text("Connection")
        }
    }

    @ViewBuilder
    private var keySection: some View {
        Section {
            if !keys.isEmpty || !selectedKeyUUID.isEmpty {
                Picker("Key", selection: $keySource) {
                    Text("Existing").tag(ServerKeySource.existing)
                    Text("New").tag(ServerKeySource.pasted)
                }
                .pickerStyle(.segmented)
            }
            if !usesPastedKey {
                Picker("Private key", selection: $selectedKeyUUID) {
                    if selectedKeyUUID.isEmpty {
                        Text("Choose").tag("")
                    }
                    ForEach(keyOptions) { key in
                        Text(key.name.isEmpty ? "Unnamed key" : key.name).tag(key.uuid)
                    }
                }
            } else {
                TextField("Key name", text: $keyName, prompt: Text("Optional"))
                TextField("Private key", text: $keyText, prompt: Text("Paste a private key"), axis: .vertical)
                    .font(.body.monospaced())
                    .lineLimit(4...10)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .textContentType(.none)
                    #endif
            }
        } header: {
            Text("Private key")
        } footer: {
            if usesPastedKey {
                Text("The key is sent to Coolify once. Hotify does not store it.")
            } else {
                Text("Coolify already has this key.")
            }
        }
    }

    private var buildServer: some View {
        Section {
            Toggle("Build server", isOn: $isBuildServer)
                .help("Coolify will not put resources on a build server.")
        } footer: {
            Text("Coolify will not put resources on a build server.")
        }
    }

    private var validate: some View {
        Section {
            Toggle("Validate immediately", isOn: $validateImmediately)
        } footer: {
            Text("Coolify checks that it can reach this server as soon as it is created.")
        }
    }

    private var capacity: some View {
        Section {
            TextField("Concurrent builds", text: $concurrentBuilds, prompt: Text("Optional"))
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            TextField("Deployment timeout", text: $deploymentTimeout, prompt: Text("Seconds"))
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            TextField("Queue limit", text: $queueLimit, prompt: Text("Optional"))
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            TextField("Disk threshold", text: $diskThreshold, prompt: Text("Percent"))
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            TextField("Disk check", text: $diskFrequency, prompt: Text("0 23 * * *"))
                .font(.body.monospaced())
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            TextField("Connection timeout", text: $connectionTimeout, prompt: Text("Seconds"))
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
        } header: {
            Text("Capacity")
        } footer: {
            Text(
                "Deployment timeout and connection timeout are seconds. Connection timeout is from 1 to 300. "
                    + "Disk threshold is a percent. Disk check is a cron expression."
            )
        }
    }

    @ViewBuilder
    private var deleteSection: some View {
        if client != nil {
            Section {
                Button("Delete Server", role: .destructive) { confirmDelete = true }
                    .disabled(isSaving)
            }
        }
    }

    @ViewBuilder
    private var notices: some View {
        if let problem {
            Section {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.glow)
            }
        }
        if let loadError {
            Section {
                Label(loadError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.glow)
                    .textSelection(.enabled)
            }
        }
        if let saveError {
            Section {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.glow)
                    .textSelection(.enabled)
            }
        }
    }

    private func load() async {
        guard let client else {
            isLoading = false
            return
        }
        isLoading = isEditing && !didSeed
        defer { isLoading = false }
        var failure: String?
        do {
            let loaded = try await client.privateKeys()
            keys = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch is CancellationError {
            return
        } catch {
            failure = (error as? CoolifyError)?.message ?? error.localizedDescription
        }
        if let serverID, !didSeed {
            do {
                apply(try await client.server(serverID))
                didSeed = true
            } catch is CancellationError {
                return
            } catch {
                failure = (error as? CoolifyError)?.message ?? error.localizedDescription
            }
        }
        let pasted = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isEditing, selectedKeyUUID.isEmpty, pasted.isEmpty, let first = keys.first {
            selectedKeyUUID = first.uuid
            keySource = .existing
        }
        if keys.isEmpty, selectedKeyUUID.isEmpty {
            keySource = .pasted
        }
        loadError = failure
    }

    private func apply(_ server: Server) {
        let values = ServerFormValues(server)
        name = values.name
        details = values.details
        ip = values.ip
        port = values.port
        userName = values.userName
        selectedKeyUUID = values.privateKeyUUID
        isBuildServer = values.isBuildServer
        concurrentBuilds = values.concurrentBuilds
        deploymentTimeout = values.deploymentTimeout
        queueLimit = values.queueLimit
        diskThreshold = values.diskThreshold
        diskFrequency = values.diskFrequency
        connectionTimeout = values.connectionTimeout
    }

    private func save() async {
        guard let client, canSave else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let keyUUID = try await resolvedKeyUUID(client)
            if let serverID {
                _ = try await client.updateServer(serverID, makeUpdate(privateKeyUUID: keyUUID))
                dismiss()
            } else {
                let created = try await client.createServer(makeDraft(privateKeyUUID: keyUUID))
                dismiss()
                onCreated(created.uuid)
            }
        } catch is CancellationError {
            return
        } catch {
            saveError = (error as? CoolifyError)?.message ?? error.localizedDescription
        }
    }

    private func delete() async {
        guard let client, let serverID else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await client.deleteServer(serverID)
            dismiss()
            onDeleted()
        } catch is CancellationError {
            return
        } catch {
            saveError = (error as? CoolifyError)?.message ?? error.localizedDescription
        }
    }

    /// Creates a pasted key, then forgets the text. A later save sends only the uuid Coolify returned.
    private func resolvedKeyUUID(_ client: CoolifyClient) async throws -> String? {
        if !usesPastedKey {
            return nilIfBlank(selectedKeyUUID)
        } else {
            let material = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !material.isEmpty else { return nil }
            let name = nilIfBlank(keyName)
            let created = try await client.createPrivateKey(PrivateKeyDraft(name: name, privateKey: material))
            keyText = ""
            keyName = ""
            selectedKeyUUID = created.uuid
            keySource = .existing
            if !keys.contains(where: { $0.uuid == created.uuid }) {
                keys.append(PrivateKeySummary(uuid: created.uuid, name: name ?? "Key"))
            }
            return created.uuid
        }
    }

    private func makeDraft(privateKeyUUID: String?) -> ServerDraft {
        ServerDraft(
            name: trimmed(name),
            description: nilIfBlank(details),
            ip: trimmed(ip),
            port: port,
            user: trimmed(userName),
            privateKeyUUID: privateKeyUUID,
            isBuildServer: isBuildServer,
            instantValidate: validateImmediately
        )
    }

    private func makeUpdate(privateKeyUUID: String?) -> ServerUpdate {
        ServerUpdate(
            name: trimmed(name),
            description: trimmed(details),
            ip: trimmed(ip),
            port: port,
            user: trimmed(userName),
            privateKeyUUID: privateKeyUUID,
            isBuildServer: isBuildServer,
            concurrentBuilds: storedNumber(concurrentBuilds),
            dynamicTimeout: storedNumber(deploymentTimeout),
            deploymentQueueLimit: storedNumber(queueLimit),
            serverDiskUsageNotificationThreshold: storedNumber(diskThreshold),
            serverDiskUsageCheckFrequency: nilIfBlank(diskFrequency),
            connectionTimeout: storedNumber(connectionTimeout)
        )
    }

    private func check(_ text: String, label: String, range: ClosedRange<Int>? = nil) -> String? {
        switch number(text) {
        case .absent:
            return nil
        case .invalid:
            return "\(label) must be a whole number."
        case .value(let value):
            if let range, !range.contains(value) {
                if range.upperBound == Int.max {
                    return "\(label) must be at least \(range.lowerBound)."
                }
                return "\(label) must be from \(range.lowerBound) to \(range.upperBound)."
            }
            if value < 0 {
                return "\(label) must be zero or more."
            }
            return nil
        }
    }

    private func storedNumber(_ text: String) -> Int? {
        if case .value(let value) = number(text) { return value }
        return nil
    }

    private func number(_ text: String) -> ServerNumberField {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .absent }
        guard let value = Int(trimmed) else { return .invalid }
        return .value(value)
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func nilIfBlank(_ text: String) -> String? {
        let trimmed = trimmed(text)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Where the sheet's private key comes from.
private enum ServerKeySource: String, Hashable {
    case existing
    case pasted
}

/// A whole number typed into a capacity field. Blank stays out of the request.
private enum ServerNumberField {
    case absent
    case invalid
    case value(Int)
}

/// The connection and capacity fields, filled from a server when Hotify already has one.
private struct ServerFormValues {
    var name = ""
    var details = ""
    var ip = ""
    var port = 22
    var userName = "root"
    var privateKeyUUID = ""
    var isBuildServer = false
    var concurrentBuilds = ""
    var deploymentTimeout = ""
    var queueLimit = ""
    var diskThreshold = ""
    var diskFrequency = ""
    var connectionTimeout = ""

    init(_ server: Server?) {
        guard let server else { return }
        name = server.name
        details = server.description ?? ""
        ip = server.ip ?? ""
        port = server.port ?? 22
        userName = server.user ?? "root"
        privateKeyUUID = server.privateKeyUUID ?? ""
        isBuildServer = server.settings?.isBuildServer ?? false
        concurrentBuilds = Self.text(server.settings?.concurrentBuilds)
        deploymentTimeout = Self.text(server.settings?.dynamicTimeout)
        queueLimit = Self.text(server.settings?.deploymentQueueLimit)
        diskThreshold = Self.text(
            server.serverDiskUsageNotificationThreshold ?? server.settings?.serverDiskUsageNotificationThreshold)
        diskFrequency =
            server.serverDiskUsageCheckFrequency ?? server.settings?.serverDiskUsageCheckFrequency ?? ""
        connectionTimeout = Self.text(server.settings?.connectionTimeout)
    }

    private static func text(_ value: Int?) -> String {
        value.map(String.init) ?? ""
    }
}

#Preview("Add") {
    ServerEditor(
        client: nil,
        keys: [
            PrivateKeySummary(uuid: "key-1", name: "lab"),
            PrivateKeySummary(uuid: "key-2", name: "edge"),
        ]
    )
}

#Preview("Edit") {
    ServerEditor(client: nil, server: ServerEditor.sample, keys: [PrivateKeySummary(uuid: "key-1", name: "lab")])
}

extension ServerEditor {
    /// A filled server for previews. It has no key material.
    private static var sample: Server {
        var server = Server(uuid: "localhost", name: "localhost", ip: "10.0.0.8", isReachable: true)
        server.description = "The lab machine"
        server.port = 22
        server.user = "root"
        server.privateKeyUUID = "key-1"
        server.serverDiskUsageNotificationThreshold = 80
        server.serverDiskUsageCheckFrequency = "0 23 * * *"
        server.settings = ServerSettings(
            isReachable: true,
            isBuildServer: false,
            concurrentBuilds: 2,
            dynamicTimeout: 3600,
            deploymentQueueLimit: 5,
            connectionTimeout: 10
        )
        return server
    }
}

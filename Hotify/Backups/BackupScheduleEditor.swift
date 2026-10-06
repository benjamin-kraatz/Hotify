import CoolifyAPI
import SwiftUI

/// Adds a database backup schedule, or changes one. A run now stays on the backup's own confirmation.
struct BackupScheduleEditor: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    var client: CoolifyClient?
    /// `nil` to add a schedule.
    var backup: DatabaseBackup?
    /// Preview supplies stores and skips the network.
    var previewStores: [S3Storage]?
    var onSave: (DatabaseBackupDraft) async throws -> Void

    @State private var preset: BackupFrequencyPreset
    @State private var customFrequency: String
    @State private var enabled: Bool
    @State private var dumpAll: Bool
    @State private var databases: String
    @State private var amountLocally: String
    @State private var daysLocally: String
    @State private var saveS3: Bool
    @State private var storeID: String
    @State private var amountS3: String
    @State private var daysS3: String
    @State private var timeoutText: String
    @State private var stores: [S3Storage] = []
    @State private var isLoadingStores = false
    @State private var storesError: String?
    @State private var isSaving = false
    @State private var saveError: String?

    init(
        client: CoolifyClient?,
        backup: DatabaseBackup?,
        previewStores: [S3Storage]? = nil,
        onSave: @escaping (DatabaseBackupDraft) async throws -> Void
    ) {
        self.client = client
        self.backup = backup
        self.previewStores = previewStores
        self.onSave = onSave
        let preset = BackupFrequencyPreset.matching(backup?.frequency)
        _preset = State(initialValue: preset)
        _customFrequency = State(initialValue: preset == .custom ? (backup?.frequency ?? "") : "")
        _enabled = State(initialValue: backup?.enabled ?? true)
        _dumpAll = State(initialValue: backup?.dumpAll ?? false)
        _databases = State(initialValue: backup?.databasesToBackup ?? "")
        _amountLocally = State(initialValue: Self.number(backup?.databaseBackupRetentionAmountLocally))
        _daysLocally = State(initialValue: Self.number(backup?.databaseBackupRetentionDaysLocally))
        _saveS3 = State(initialValue: backup?.saveS3 ?? false)
        _storeID = State(initialValue: backup?.s3StorageUUID ?? "")
        _amountS3 = State(initialValue: Self.number(backup?.databaseBackupRetentionAmountS3))
        _daysS3 = State(initialValue: Self.number(backup?.databaseBackupRetentionDaysS3))
        _timeoutText = State(initialValue: backup?.timeout.map(String.init) ?? "3600")
    }

    private var isNew: Bool { backup == nil }

    private var frequency: String {
        if preset == .custom {
            return customFrequency.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return preset.rawValue
    }

    /// An existing remote backup can keep its store when Coolify's list did not name the uuid.
    private var needsStoreChoice: Bool {
        guard saveS3, storeID.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if backup?.saveS3 == true { return false }
        return true
    }

    private var problems: [String] {
        var problems: [String] = []
        if frequency.isEmpty {
            problems.append("Enter a frequency.")
        }
        if let timeoutProblem {
            problems.append(timeoutProblem)
        }
        if let problem = retentionProblem(amountLocally, original: backup?.databaseBackupRetentionAmountLocally) {
            problems.append(problem)
        }
        if let problem = retentionProblem(daysLocally, original: backup?.databaseBackupRetentionDaysLocally) {
            problems.append(problem)
        }
        if saveS3 {
            if let problem = retentionProblem(amountS3, original: backup?.databaseBackupRetentionAmountS3) {
                problems.append(problem)
            }
            if let problem = retentionProblem(daysS3, original: backup?.databaseBackupRetentionDaysS3) {
                problems.append(problem)
            }
        }
        if needsStoreChoice {
            problems.append("Choose an S3 store.")
        }
        return problems
    }

    private var timeoutProblem: String? {
        guard let value = Int(timeoutText.trimmingCharacters(in: .whitespaces)) else {
            return "Enter a timeout in seconds."
        }
        if value < 60 || value > 36000 {
            return "Timeout has to be from 60 to 36000 seconds."
        }
        return nil
    }

    private var canSave: Bool {
        guard problems.isEmpty, !isSaving else { return false }
        if isNew { return true }
        return !makeDraft().isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                schedule
                databasesSection
                localRetention
                remote
                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.glow)
                            .textSelection(.enabled)
                    }
                }
                if !problems.isEmpty {
                    Section {
                        ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
                            Label(problem, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.glow)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "New Schedule" : "Edit Schedule")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button(isNew ? "Add" : "Save") {
                            Task { await save() }
                        }
                        .disabled(!canSave)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: dumpAll)
            .animation(reduceMotion ? nil : .snappy, value: saveS3)
            .animation(reduceMotion ? nil : .snappy, value: saveError)
            .task { await loadStores() }
            .onChange(of: editToken) { _, _ in saveError = nil }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 560)
        #endif
    }

    private var schedule: some View {
        Section {
            Picker("Frequency", selection: $preset) {
                ForEach(BackupFrequencyPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            if preset == .custom {
                TextField("Cron expression", text: $customFrequency, prompt: Text(verbatim: "0 2 * * *"))
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    #if os(iOS)
                .textInputAutocapitalization(.never)
                    #endif
            }
            Toggle(isOn: $enabled) {
                Text("Enabled")
                Text("Runs on this schedule. Turn it off to keep the schedule without running it.")
            }
            TextField("Timeout", text: $timeoutText, prompt: Text(verbatim: "3600"))
                .monospacedDigit()
                .autocorrectionDisabled()
                #if os(iOS)
            .keyboardType(.numberPad)
            .textInputAutocapitalization(.never)
                #endif
        } header: {
            Text("Schedule")
        } footer: {
            Text("Seconds Coolify waits for the dump. From 60 to 36000.")
        }
    }

    private var databasesSection: some View {
        Section {
            Toggle(isOn: $dumpAll) {
                Text("Dump all databases")
                Text("Include every database, not a named list.")
            }
            if !dumpAll {
                TextField("Databases", text: $databases, prompt: Text(verbatim: "app, analytics"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                .textInputAutocapitalization(.never)
                    #endif
            }
        } header: {
            Text("Databases")
        } footer: {
            Text("Comma-separated. On a new schedule, an empty list uses the database's own name.")
        }
    }

    private var localRetention: some View {
        Section {
            RetentionField(title: "Number to keep", text: $amountLocally)
            RetentionField(title: "Days to keep", text: $daysLocally)
        } header: {
            Text("On the server")
        } footer: {
            Text("How many dumps to keep, and for how many days.")
        }
    }

    private var remote: some View {
        Section {
            Toggle("Copy to S3", isOn: $saveS3)
            if saveS3 {
                if isLoadingStores {
                    ProgressView()
                } else {
                    Picker("Store", selection: $storeID) {
                        Text("Choose a store").tag("")
                        ForEach(stores) { store in
                            Text(storeLabel(store)).tag(store.id)
                        }
                    }
                    RetentionField(title: "Number to keep in S3", text: $amountS3)
                    RetentionField(title: "Days to keep in S3", text: $daysS3)
                }
                if let storesError {
                    Label(storesError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.glow)
                }
            }
        } header: {
            Text("Remote")
        } footer: {
            Text(remoteFooter)
        }
    }

    private var remoteFooter: String {
        if saveS3, stores.isEmpty, !isLoadingStores, storesError == nil {
            return "Add an S3 store in Settings, then choose it here."
        }
        if saveS3, storeID.isEmpty, backup?.saveS3 == true {
            return "The current store stays until you pick a different one."
        }
        return "Copies each dump to a store shared by the team."
    }

    private var editToken: String {
        [
            preset.rawValue, customFrequency, String(enabled), String(dumpAll), databases, String(saveS3), storeID,
            timeoutText, amountLocally, daysLocally, amountS3, daysS3,
        ].joined(separator: "|")
    }

    private func loadStores() async {
        if let previewStores {
            stores = previewStores
            return
        }
        guard let client else { return }
        isLoadingStores = true
        defer { isLoadingStores = false }
        do {
            stores = try await client.s3Storages()
        } catch is CancellationError {
            return
        } catch {
            storesError = (error as? CoolifyError)?.summary ?? error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(makeDraft())
            dismiss()
        } catch {
            saveError = (error as? CoolifyError)?.summary ?? error.localizedDescription
        }
    }

    /// Fields the user left alone stay nil, so the update does not send them and does not send `backup_now`.
    private func makeDraft() -> DatabaseBackupDraft {
        var draft = DatabaseBackupDraft()
        if isNew || frequency != (backup?.frequency ?? "") {
            draft.frequency = frequency
        }
        if isNew || enabled != (backup?.enabled ?? true) {
            draft.enabled = enabled
        }
        if dumpAll != (backup?.dumpAll ?? false) {
            draft.dumpAll = dumpAll
        }
        if !dumpAll {
            let next = trimmed(databases)
            let original = trimmed(backup?.databasesToBackup ?? "")
            if isNew {
                if !next.isEmpty { draft.databasesToBackup = next }
            } else if next != original {
                draft.databasesToBackup = next
            }
        }
        applyRetention(amountLocally, original: backup?.databaseBackupRetentionAmountLocally) {
            draft.databaseBackupRetentionAmountLocally = $0
        }
        applyRetention(daysLocally, original: backup?.databaseBackupRetentionDaysLocally) {
            draft.databaseBackupRetentionDaysLocally = $0
        }
        if let value = Int(trimmed(timeoutText)) {
            let baseline = backup?.timeout ?? 3600
            if isNew || value != baseline {
                draft.timeout = value
            }
        }
        let originalSave = backup?.saveS3 ?? false
        if saveS3 != originalSave {
            draft.saveS3 = saveS3
        }
        if saveS3 {
            let chosen = trimmed(storeID)
            // Turning the copy on has to name the store in the same request, or Coolify answers 422.
            if !chosen.isEmpty && (chosen != (backup?.s3StorageUUID ?? "") || draft.saveS3 == true) {
                draft.s3StorageUUID = chosen
            }
            applyRetention(amountS3, original: backup?.databaseBackupRetentionAmountS3) {
                draft.databaseBackupRetentionAmountS3 = $0
            }
            applyRetention(daysS3, original: backup?.databaseBackupRetentionDaysS3) {
                draft.databaseBackupRetentionDaysS3 = $0
            }
        }
        return draft
    }

    private func applyRetention(_ text: String, original: Int?, assign: (Int) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = Int(trimmed), value >= 0 else { return }
        if isNew || value != original {
            assign(value)
        }
    }

    private func retentionProblem(_ text: String, original: Int?) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return original == nil ? nil : "Enter a whole number, zero or more."
        }
        guard let value = Int(trimmed), value >= 0 else {
            return "Enter a whole number, zero or more."
        }
        return nil
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func storeLabel(_ store: S3Storage) -> String {
        store.isUsable ? "\(store.name) · \(store.bucket)" : "\(store.name) · \(store.bucket), not usable"
    }

    private static func number(_ value: Int?) -> String {
        value.map(String.init) ?? ""
    }
}

private struct RetentionField: View {
    var title: String
    @Binding var text: String

    var body: some View {
        TextField(title, text: $text)
            .monospacedDigit()
            .autocorrectionDisabled()
            #if os(iOS)
        .keyboardType(.numberPad)
        .textInputAutocapitalization(.never)
            #endif
    }
}

private enum BackupFrequencyPreset: String, CaseIterable, Identifiable {
    case everyMinute = "every_minute"
    case hourly
    case daily
    case weekly
    case monthly
    case yearly
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyMinute: "Every minute"
        case .hourly: "Every hour"
        case .daily: "Every day"
        case .weekly: "Every week"
        case .monthly: "Every month"
        case .yearly: "Every year"
        case .custom: "Custom"
        }
    }

    static func matching(_ frequency: String?) -> BackupFrequencyPreset {
        guard let frequency, !frequency.isEmpty else { return .daily }
        return Self(rawValue: frequency) ?? .custom
    }
}

#Preview("New") {
    BackupScheduleEditor(client: nil, backup: nil, previewStores: schedulePreviewStores, onSave: { _ in })
}

#Preview("Edit") {
    BackupScheduleEditor(
        client: nil,
        backup: schedulePreviewBackup,
        previewStores: schedulePreviewStores,
        onSave: { _ in }
    )
}

private let schedulePreviewStores = [
    S3Storage(
        uuid: "store-1",
        name: "Backups",
        endpoint: "https://s3.example.com",
        bucket: "dumps",
        region: "us-east-1",
        isUsable: true
    )
]

private var schedulePreviewBackup: DatabaseBackup {
    let json = """
        {"uuid":"daily","enabled":true,"frequency":"daily","databasesToBackup":"app,analytics","dumpAll":false,
         "saveS3":false,"timeout":3600,"databaseBackupRetentionAmountLocally":7,
         "databaseBackupRetentionDaysLocally":14,"executions":[]}
        """
    return try! JSONDecoder().decode(DatabaseBackup.self, from: Data(json.utf8))
}

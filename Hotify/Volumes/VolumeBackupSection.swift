import CoolifyAPI
import SwiftUI

/// Frequency, retention, and an optional S3 copy for one volume or directory mount.
///
/// Coolify has no documented GET for this schedule. `schedule` is the nested one, or the last PUT in the session.
struct VolumeBackupSection: View {
    var resourceName: String
    var schedule: VolumeBackupSchedule?
    var stores: [S3Storage]
    var didLoadStores: Bool
    var isLoadingStores: Bool
    var storesError: String?
    var onLoadStores: () async -> Void
    var onSave: (VolumeBackupScheduleRequest) async throws -> Void
    var onDelete: () async throws -> Void
    var onRun: () async throws -> Void

    @State private var cadence: BackupCadence
    @State private var cron: String
    @State private var enabled: Bool
    @State private var stopDuringBackup: Bool
    @State private var confirmStop = false
    @State private var copies: String
    @State private var days: String
    @State private var maxStorage: String
    @State private var saveS3: Bool
    @State private var s3StorageUuid: String?
    @State private var s3Copies: String
    @State private var s3Days: String
    @State private var s3MaxStorage: String
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var confirmRun = false
    @State private var confirmDelete = false

    init(
        resourceName: String,
        schedule: VolumeBackupSchedule?,
        stores: [S3Storage],
        didLoadStores: Bool,
        isLoadingStores: Bool,
        storesError: String?,
        onLoadStores: @escaping () async -> Void,
        onSave: @escaping (VolumeBackupScheduleRequest) async throws -> Void,
        onDelete: @escaping () async throws -> Void,
        onRun: @escaping () async throws -> Void
    ) {
        self.resourceName = resourceName
        self.schedule = schedule
        self.stores = stores
        self.didLoadStores = didLoadStores
        self.isLoadingStores = isLoadingStores
        self.storesError = storesError
        self.onLoadStores = onLoadStores
        self.onSave = onSave
        self.onDelete = onDelete
        self.onRun = onRun
        let matched = BackupCadence.match(schedule?.frequency)
        _cadence = State(initialValue: matched.cadence)
        _cron = State(initialValue: matched.cron)
        _enabled = State(initialValue: schedule?.enabled ?? true)
        _stopDuringBackup = State(initialValue: schedule?.stopDuringBackup ?? false)
        _copies = State(initialValue: Self.text(schedule?.retentionAmountLocally))
        _days = State(initialValue: Self.text(schedule?.retentionDaysLocally))
        _maxStorage = State(initialValue: Self.text(schedule?.retentionMaxStorageLocally))
        _saveS3 = State(initialValue: schedule?.saveS3 ?? false)
        _s3StorageUuid = State(initialValue: schedule?.s3StorageUuid)
        _s3Copies = State(initialValue: Self.text(schedule?.retentionAmountS3))
        _s3Days = State(initialValue: Self.text(schedule?.retentionDaysS3))
        _s3MaxStorage = State(initialValue: Self.text(schedule?.retentionMaxStorageS3))
    }

    private var frequency: String {
        cadence == .custom ? cron.trimmingCharacters(in: .whitespacesAndNewlines) : cadence.rawValue
    }

    private var canSave: Bool {
        !frequency.isEmpty && !isSaving && !(saveS3 && (s3StorageUuid ?? "").isEmpty)
    }

    var body: some View {
        Section {
            Picker("Frequency", selection: $cadence) {
                ForEach(BackupCadence.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            if cadence == .custom {
                TextField("Cron", text: $cron, prompt: Text(verbatim: "0 2 * * *"))
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }
            Toggle("Enabled", isOn: $enabled)
            Toggle(isOn: stopBinding) {
                Text("Stop during backup")
                Text("Coolify stops \(resourceName) while it copies this volume, then starts it again.")
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("Hourly through yearly, or a cron expression.")
        }

        Section {
            numberField("Copies to keep", text: $copies)
            numberField("Days to keep", text: $days)
            numberField("Max storage (GB)", text: $maxStorage)
        } header: {
            Text("Local retention")
        } footer: {
            Text("Empty leaves Coolify's default.")
        }

        Section {
            Toggle("Copy to S3", isOn: $saveS3)
            if saveS3 {
                storesPicker
                numberField("S3 copies to keep", text: $s3Copies)
                numberField("S3 days to keep", text: $s3Days)
                numberField("S3 max storage (GB)", text: $s3MaxStorage)
            }
        } footer: {
            if saveS3, didLoadStores, stores.isEmpty {
                Text("Backup stores are added in Settings.")
            }
        }

        Section {
            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.glow)
            }
            Button(schedule == nil ? "Set Schedule" : "Replace Schedule") {
                Task { await save() }
            }
            .disabled(!canSave)
            Button("Run Now") { confirmRun = true }
                .disabled(schedule == nil || isSaving)
            Button("Delete Schedule", role: .destructive) { confirmDelete = true }
                .disabled(schedule == nil || isSaving)
        }
        .confirmationDialog(
            "Stop \(resourceName) during backup?",
            isPresented: $confirmStop,
            titleVisibility: .visible
        ) {
            Button("Stop During Backup") { stopDuringBackup = true }
        } message: {
            Text("Coolify stops \(resourceName) while it copies this volume, then starts it again.")
        }
        .confirmationDialog(
            "Back up this volume now?",
            isPresented: $confirmRun,
            titleVisibility: .visible
        ) {
            Button("Back Up Now") { Task { await run() } }
        } message: {
            Text("Coolify runs this volume backup once, using the schedule already saved.")
        }
        .confirmationDialog(
            "Delete this backup schedule?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Schedule", role: .destructive) { Task { await delete() } }
        } message: {
            Text("Coolify deletes the schedule and the archives it kept for this volume.")
        }
        .task {
            guard saveS3 else { return }
            await onLoadStores()
        }
        .onChange(of: saveS3) { _, isOn in
            guard isOn else { return }
            Task { await onLoadStores() }
        }
        .onChange(of: schedule) { _, new in
            apply(new)
        }
    }

    private func apply(_ schedule: VolumeBackupSchedule?) {
        let matched = BackupCadence.match(schedule?.frequency)
        cadence = matched.cadence
        cron = matched.cron
        enabled = schedule?.enabled ?? true
        stopDuringBackup = schedule?.stopDuringBackup ?? false
        copies = Self.text(schedule?.retentionAmountLocally)
        days = Self.text(schedule?.retentionDaysLocally)
        maxStorage = Self.text(schedule?.retentionMaxStorageLocally)
        saveS3 = schedule?.saveS3 ?? false
        s3StorageUuid = schedule?.s3StorageUuid
        s3Copies = Self.text(schedule?.retentionAmountS3)
        s3Days = Self.text(schedule?.retentionDaysS3)
        s3MaxStorage = Self.text(schedule?.retentionMaxStorageS3)
    }

    private var stopBinding: Binding<Bool> {
        Binding(
            get: { stopDuringBackup },
            set: { isOn in
                if isOn {
                    confirmStop = true
                } else {
                    stopDuringBackup = false
                }
            }
        )
    }

    @ViewBuilder
    private var storesPicker: some View {
        if isLoadingStores, !didLoadStores {
            ProgressView()
        } else if let storesError {
            Label(storesError, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.glow)
            Button("Try Again") { Task { await onLoadStores() } }
        } else if didLoadStores, stores.isEmpty {
            Text("Backup stores are added in Settings.")
                .foregroundStyle(.secondary)
        } else {
            Picker("Backup store", selection: $s3StorageUuid) {
                Text("Choose a store").tag(Optional<String>.none)
                ForEach(stores) { store in
                    Text(store.name.isEmpty ? store.bucket : store.name).tag(Optional(store.uuid))
                }
            }
        }
    }

    private func numberField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        let request = VolumeBackupScheduleRequest(
            frequency: frequency,
            enabled: enabled,
            saveS3: saveS3,
            stopDuringBackup: stopDuringBackup,
            s3StorageUuid: saveS3 ? s3StorageUuid : nil,
            retentionAmountLocally: Self.whole(copies),
            retentionDaysLocally: Self.whole(days),
            retentionMaxStorageLocally: Self.amount(maxStorage),
            retentionAmountS3: saveS3 ? Self.whole(s3Copies) : nil,
            retentionDaysS3: saveS3 ? Self.whole(s3Days) : nil,
            retentionMaxStorageS3: saveS3 ? Self.amount(s3MaxStorage) : nil
        )
        do {
            try await onSave(request)
            saveError = nil
        } catch is CancellationError {
            return
        } catch {
            saveError = (error as? CoolifyError)?.message ?? error.localizedDescription
        }
    }

    private func delete() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await onDelete()
            saveError = nil
        } catch is CancellationError {
            return
        } catch {
            saveError = (error as? CoolifyError)?.message ?? error.localizedDescription
        }
    }

    private func run() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await onRun()
            saveError = nil
        } catch is CancellationError {
            return
        } catch {
            saveError = (error as? CoolifyError)?.message ?? error.localizedDescription
        }
    }

    private static func text(_ value: Int?) -> String {
        value.map(String.init) ?? ""
    }

    private static func text(_ value: Double?) -> String {
        guard let value else { return "" }
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }

    private static func whole(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }

    private static func amount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }
}

/// A backup frequency Coolify accepts: a preset word, or a cron expression.
private enum BackupCadence: String, CaseIterable, Identifiable {
    case hourly
    case daily
    case weekly
    case monthly
    case yearly
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hourly: "Hourly"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        case .custom: "Custom"
        }
    }

    static func match(_ frequency: String?) -> (cadence: BackupCadence, cron: String) {
        guard let frequency, !frequency.isEmpty else { return (.daily, "") }
        if let preset = BackupCadence(rawValue: frequency.lowercased()), preset != .custom {
            return (preset, "")
        }
        return (.custom, frequency)
    }
}

#Preview("Schedule") {
    Form {
        VolumeBackupSection(
            resourceName: "marketing-site",
            schedule: VolumeBackupSchedule(uuid: "bak", frequency: "daily", retentionAmountLocally: 7),
            stores: [
                S3Storage(
                    uuid: "s3", name: "Backups", endpoint: "https://s3.example.com", bucket: "backups",
                    region: "us-east-1", isUsable: true)
            ],
            didLoadStores: true,
            isLoadingStores: false,
            storesError: nil,
            onLoadStores: {},
            onSave: { _ in },
            onDelete: {},
            onRun: {}
        )
    }
    .frame(width: 480, height: 640)
}

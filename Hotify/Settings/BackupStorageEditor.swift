import CoolifyAPI
import SwiftUI

/// Adds an S3-compatible backup store, or changes one. A blank key or secret on edit keeps the stored credential.
struct BackupStorageEditor: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss

    /// `nil` to add a store.
    var storage: S3Storage?
    var onCreate: (S3StorageDraft) async throws -> Void
    var onUpdate: (S3StorageUpdate) async throws -> Void

    @State private var name: String
    @State private var details: String
    @State private var endpoint: String
    @State private var bucket: String
    @State private var region: String
    @State private var key: String
    @State private var secret: String
    @State private var isUsable: Bool
    @State private var isSaving = false
    @State private var saveError: String?

    init(
        storage: S3Storage?,
        onCreate: @escaping (S3StorageDraft) async throws -> Void,
        onUpdate: @escaping (S3StorageUpdate) async throws -> Void
    ) {
        self.storage = storage
        self.onCreate = onCreate
        self.onUpdate = onUpdate
        _name = State(initialValue: storage?.name ?? "")
        _details = State(initialValue: storage?.description ?? "")
        _endpoint = State(initialValue: storage?.endpoint ?? "")
        _bucket = State(initialValue: storage?.bucket ?? "")
        _region = State(initialValue: storage?.region ?? "")
        // The list response has neither credential, so both start blank.
        _key = State(initialValue: "")
        _secret = State(initialValue: "")
        _isUsable = State(initialValue: storage?.isUsable ?? true)
    }

    private var isNew: Bool { storage == nil }

    private var problem: String? {
        if trimmed(name).isEmpty { return "Enter a name." }
        if trimmed(endpoint).isEmpty { return "Enter an endpoint." }
        if trimmed(bucket).isEmpty { return "Enter a bucket." }
        if trimmed(region).isEmpty { return "Enter a region." }
        if isNew, trimmed(key).isEmpty { return "Enter an access key." }
        if isNew, trimmed(secret).isEmpty { return "Enter a secret." }
        return nil
    }

    private var canSave: Bool {
        guard problem == nil, !isSaving else { return false }
        if isNew { return true }
        return !makeUpdate().isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Backups"))
                    TextField("Description", text: $details, prompt: Text("Optional"))
                    TextField("Endpoint", text: $endpoint, prompt: Text(verbatim: "https://s3.example.com"))
                        .autocorrectionDisabled()
                        #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                        #endif
                    TextField("Bucket", text: $bucket, prompt: Text(verbatim: "dumps"))
                        .autocorrectionDisabled()
                        #if os(iOS)
                    .textInputAutocapitalization(.never)
                        #endif
                    TextField("Region", text: $region, prompt: Text(verbatim: "us-east-1"))
                        .autocorrectionDisabled()
                        #if os(iOS)
                    .textInputAutocapitalization(.never)
                        #endif
                    Toggle(isOn: $isUsable) {
                        Text("Usable")
                        Text("Backups can copy to a store only when it is usable.")
                    }
                } header: {
                    Text("Store")
                }

                Section {
                    TextField("Access key", text: $key, prompt: Text(isNew ? "Access key" : "Leave blank to keep it"))
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .textContentType(.none)
                        #endif
                    SecureField(
                        "Secret",
                        text: $secret,
                        prompt: Text(isNew ? "Secret" : "Leave blank to keep it")
                    )
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .textContentType(.none)
                    #endif
                } header: {
                    Text("Credentials")
                } footer: {
                    Text(
                        isNew
                            ? "Coolify keeps the secret on the instance. Hotify does not store it."
                            : "Leave the key and secret blank to keep the ones Coolify has."
                    )
                }

                if let problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.glow)
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
            .formStyle(.grouped)
            .navigationTitle(isNew ? "New Store" : "Edit Store")
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
            .onChange(of: name) { _, _ in saveError = nil }
            .onChange(of: details) { _, _ in saveError = nil }
            .onChange(of: endpoint) { _, _ in saveError = nil }
            .onChange(of: bucket) { _, _ in saveError = nil }
            .onChange(of: region) { _, _ in saveError = nil }
            .onChange(of: key) { _, _ in saveError = nil }
            .onChange(of: secret) { _, _ in saveError = nil }
            .onChange(of: isUsable) { _, _ in saveError = nil }
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 500, minHeight: 520)
        #endif
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            if storage == nil {
                try await onCreate(makeDraft())
            } else {
                try await onUpdate(makeUpdate())
            }
            dismiss()
        } catch {
            saveError = (error as? CoolifyError)?.summary ?? error.localizedDescription
        }
    }

    /// Sends the usable flag. Coolify stores false when a create omits it.
    private func makeDraft() -> S3StorageDraft {
        S3StorageDraft(
            name: trimmed(name),
            description: nilIfBlank(details),
            endpoint: trimmed(endpoint),
            bucket: trimmed(bucket),
            region: trimmed(region),
            key: trimmed(key),
            secret: trimmed(secret),
            isUsable: isUsable
        )
    }

    private func makeUpdate() -> S3StorageUpdate {
        guard let storage else { return S3StorageUpdate() }
        var update = S3StorageUpdate()
        let nextName = trimmed(name)
        if nextName != storage.name { update.name = nextName }
        let nextDetails = trimmed(details)
        if nextDetails != (storage.description ?? "") { update.description = nextDetails }
        let nextEndpoint = trimmed(endpoint)
        if nextEndpoint != storage.endpoint { update.endpoint = nextEndpoint }
        let nextBucket = trimmed(bucket)
        if nextBucket != storage.bucket { update.bucket = nextBucket }
        let nextRegion = trimmed(region)
        if nextRegion != storage.region { update.region = nextRegion }
        let nextKey = trimmed(key)
        if !nextKey.isEmpty { update.key = nextKey }
        let nextSecret = trimmed(secret)
        if !nextSecret.isEmpty { update.secret = nextSecret }
        if isUsable != storage.isUsable { update.isUsable = isUsable }
        return update
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func nilIfBlank(_ text: String) -> String? {
        let trimmed = trimmed(text)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview("New") {
    BackupStorageEditor(storage: nil, onCreate: { _ in }, onUpdate: { _ in })
}

#Preview("Edit") {
    BackupStorageEditor(
        storage: S3Storage(
            uuid: "store-1",
            name: "Backups",
            description: "Nightly dumps",
            endpoint: "https://s3.example.com",
            bucket: "dumps",
            region: "us-east-1",
            isUsable: true
        ),
        onCreate: { _ in },
        onUpdate: { _ in }
    )
}

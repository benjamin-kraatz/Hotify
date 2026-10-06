import CoolifyAPI
import SwiftUI

/// Edits one compose container. An application container takes a name and domains. A database container takes a name
/// and, when it should be reachable, a public port.
struct ContainerEditor: View {
    var container: ContainerSummary
    var values: ContainerEditorValues
    var client: CoolifyClient?
    var serviceUUID: String?
    var onSaved: (ContainerEditorValues) -> Void = { _ in }

    @SwiftUI.Environment(\.dismiss) private var dismiss
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var name: String
    @State private var domains: [String]
    @State private var isPublic: Bool
    @State private var publicPort: Int?
    @State private var conflicts: [DomainConflict] = []
    @State private var saveError: String?
    @State private var isSaving = false

    init(
        container: ContainerSummary,
        values: ContainerEditorValues,
        client: CoolifyClient? = nil,
        serviceUUID: String? = nil,
        onSaved: @escaping (ContainerEditorValues) -> Void = { _ in }
    ) {
        self.container = container
        self.values = values
        self.client = client
        self.serviceUUID = serviceUUID
        self.onSaved = onSaved
        _name = State(initialValue: values.name)
        _domains = State(initialValue: values.domains)
        _isPublic = State(initialValue: values.isPublic)
        _publicPort = State(initialValue: values.publicPort)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                notices
                form
            }
            .navigationTitle("Edit Container")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save(force: false) } }
                        .disabled(!canSave)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 500, minHeight: 440)
        #endif
        .animation(reduceMotion ? nil : .snappy, value: isPublic)
        .animation(reduceMotion ? nil : .snappy, value: conflicts)
        .animation(reduceMotion ? nil : .snappy, value: saveError)
    }

    @ViewBuilder
    private var notices: some View {
        if problem != nil || !conflicts.isEmpty || saveError != nil {
            VStack(spacing: 8) {
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.glow)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !conflicts.isEmpty {
                    ProblemNotice(problem: .conflicts(conflicts)) {
                        Task { await save(force: true) }
                    }
                }
                if let saveError {
                    NoticeBanner(message: saveError)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
    }

    private var form: some View {
        Form {
            Section("General") {
                TextField("Name", text: $name, prompt: Text("Name"))
                    .autocorrectionDisabled()
            }
            if container.isDatabase {
                publicAccess
            } else {
                domainsSection
            }
        }
        .formStyle(.grouped)
        .disabled(isSaving)
    }

    private var domainsSection: some View {
        Section {
            DomainListEditor(domains: $domains, owner: container.name)
        } header: {
            DomainSectionHeader(title: "Domains", domains: $domains, owner: container.name)
        } footer: {
            Text(
                "Coolify routes these to the container through the server's proxy. Changes take effect after a restart."
            )
        }
    }

    private var publicAccess: some View {
        Section {
            Toggle("Reachable from the internet", isOn: $isPublic)
            if isPublic {
                NumberField(title: "Public port", value: $publicPort, prompt: "5432")
            }
        } header: {
            Text("Public Access")
        } footer: {
            Text(
                isPublic
                    ? "Coolify forwards this port on the server to the database. Anyone who can reach the server "
                        + "can try to sign in, so keep its password strong."
                    : "Only resources on the server's network can reach the database."
            )
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var savedName: String {
        values.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var joinedDomains: String {
        ResourceConfiguration.joined(domains)
    }

    private var savedDomains: String {
        ResourceConfiguration.joined(values.domains)
    }

    private var hasChanges: Bool {
        if trimmedName != savedName { return true }
        if container.isDatabase {
            if isPublic != values.isPublic { return true }
            if isPublic, publicPort != values.publicPort { return true }
            return false
        }
        return joinedDomains != savedDomains
    }

    /// The first thing Coolify would refuse, worded for the person editing.
    private var problem: String? {
        if trimmedName.isEmpty {
            return "A name is required."
        }
        if container.isDatabase {
            if isPublic, publicPort == nil {
                return "Public access needs a port."
            }
            if let publicPort, isPublic, !(1...65_535).contains(publicPort) {
                return "A port is a number from 1 to 65535."
            }
            return nil
        }
        if let bad = domains.map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: {
            !$0.isEmpty && !ResourceConfiguration.isWebAddress($0)
        }) {
            return "\(bad) isn't a web address. It needs http:// or https:// and a host."
        }
        return nil
    }

    private var canSave: Bool {
        client != nil && serviceUUID?.isEmpty == false && !container.uuid.isEmpty && hasChanges && problem == nil
            && !isSaving
    }

    /// Skips the call when there is no client or no uuid, so a numeric id never reaches the path.
    private func save(force: Bool) async {
        guard !isSaving, let client, let serviceUUID, !serviceUUID.isEmpty, !container.uuid.isEmpty else { return }
        guard problem == nil else { return }
        let application = applicationUpdate
        let database = databaseUpdate
        if container.isDatabase ? database.isEmpty : application.isEmpty {
            dismiss()
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            if container.isDatabase {
                try await client.updateServiceDatabase(serviceUUID, uuid: container.uuid, database)
            } else {
                // Coolify reads the override from the query and answers 422 if it arrives in the body.
                try await client.updateServiceApplication(
                    serviceUUID,
                    uuid: container.uuid,
                    application,
                    forceDomainOverride: force && application.url != nil
                )
            }
        } catch let error as CoolifyError where error.statusCode == 409 && !error.conflicts.isEmpty {
            conflicts = error.conflicts
            saveError = nil
            return
        } catch is CancellationError {
            return
        } catch {
            conflicts = []
            saveError = (error as? CoolifyError)?.summary ?? error.localizedDescription
            return
        }
        conflicts = []
        saveError = nil
        onSaved(
            ContainerEditorValues(
                name: trimmedName,
                domains: ResourceConfiguration.split(joinedDomains),
                isPublic: isPublic,
                publicPort: publicPort
            )
        )
        dismiss()
    }

    private var applicationUpdate: ServiceContainerApplicationUpdate {
        var update = ServiceContainerApplicationUpdate()
        if trimmedName != savedName { update.humanName = trimmedName }
        if joinedDomains != savedDomains { update.url = joinedDomains }
        return update
    }

    private var databaseUpdate: ServiceContainerDatabaseUpdate {
        var update = ServiceContainerDatabaseUpdate()
        if trimmedName != savedName { update.humanName = trimmedName }
        if isPublic != values.isPublic {
            update.isPublic = isPublic
            // Coolify only starts the proxy when the port comes with the switch.
            if isPublic { update.publicPort = publicPort }
        } else if isPublic, publicPort != values.publicPort {
            update.publicPort = publicPort
        }
        return update
    }
}

#Preview("Application container") {
    ContainerEditor(
        container: ContainerSummary(
            id: 1,
            name: "dashboard",
            serviceName: "dashboard",
            status: "running:healthy",
            uuid: "app-1"
        ),
        values: ContainerEditorValues(
            name: "dashboard",
            domains: ["https://convex.example.com", "https://www.convex.example.com"],
            isPublic: false,
            publicPort: nil
        )
    )
}

#Preview("Database container") {
    ContainerEditor(
        container: ContainerSummary(
            id: -2,
            name: "postgres",
            serviceName: "postgres",
            status: "running:healthy",
            uuid: "db-1",
            isDatabase: true,
            isPublic: true,
            publicPort: 5432
        ),
        values: ContainerEditorValues(
            name: "postgres",
            domains: [],
            isPublic: true,
            publicPort: 5432
        )
    )
}

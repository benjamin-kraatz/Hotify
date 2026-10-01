import CoolifyAPI
import SwiftUI

/// The service exists, stopped. Here the user gives it addresses and fills in its settings, then starts it.
struct ServiceSetup: View {
    var model: ProvisioningModel
    /// Closes provisioning and opens the service, or nothing when it was deleted.
    var onClose: (ResourceRoute?) -> Void

    @State private var revealed: Set<String> = []
    @State private var isConfirmingCancel = false

    private var displayName: String { model.template?.displayName ?? model.serviceName }

    private var place: String {
        let placement = model.placement
        let project = placement.project?.name ?? ""
        let environment = placement.environment?.name ?? ""
        return environment.isEmpty ? project : "\(project) · \(environment)"
    }

    private var isBusy: Bool { model.isSaving || model.isDiscarding }

    var body: some View {
        @Bindable var model = model

        Form {
            Section {
                if model.isLoadingSetup, model.setup.domains.isEmpty {
                    loadingRow("Reading its addresses…")
                }
                ForEach($model.setup.domains) { $domain in
                    if domain.isPublic || revealed.contains(domain.id) {
                        DomainRow(domain: $domain)
                    }
                }
                ForEach(model.setup.domains.filter { !$0.isPublic && !revealed.contains($0.id) }) { domain in
                    InternalContainerRow(domain: domain) {
                        revealed.insert(domain.id)
                    }
                }
            } header: {
                hero
            } footer: {
                Text(
                    "Separate several addresses with commas. Coolify gets a certificate for an https address once its DNS points at the server."
                )
            }

            Section {
                if model.isLoadingSetup, model.setup.settings.isEmpty {
                    loadingRow("Reading its settings…")
                } else if model.setup.settings.isEmpty {
                    Text("Nothing to fill in. \(displayName) runs as it is.")
                        .foregroundStyle(.secondary)
                }
                ForEach($model.setup.settings) { $variable in
                    SettingRow(variable: $variable)
                }
            } header: {
                Text("Settings")
            } footer: {
                if !model.setup.missingKeys.isEmpty {
                    Text("Compose won't start \(displayName) until every required setting has a value.")
                }
            }

            if !model.setup.generated.isEmpty {
                Section {
                    DisclosureGroup {
                        ForEach(model.setup.generated) { variable in
                            HStack {
                                Text(verbatim: variable.key)
                                    .font(.callout.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 12)
                                Text(variable.isHidden ? "Hidden" : "Generated")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    } label: {
                        Label(
                            "\(model.setup.generated.count) passwords, users, and addresses",
                            systemImage: "key.viewfinder"
                        )
                    }
                } header: {
                    Text("Made by Coolify")
                } footer: {
                    Text("Coolify made these for \(displayName). Change them later under Variables.")
                }
            }

            if let problem = model.setupProblem {
                Section {
                    ProblemNotice(problem: problem, instanceRoot: model.instanceRoot) {
                        Task { await model.startSharingDomains() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .disabled(isBusy)
        .safeAreaInset(edge: .bottom, spacing: 0) { startBar }
        .animation(.snappy, value: model.setupProblem)
        .animation(.snappy, value: revealed)
        .navigationTitle(model.serviceName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { isConfirmingCancel = true }
                    .disabled(isBusy)
            }
        }
        .confirmationDialog(
            "\(model.serviceName) is already in Coolify",
            isPresented: $isConfirmingCancel,
            titleVisibility: .visible
        ) {
            Button("Keep It, Stopped") { onClose(model.route) }
            Button("Delete \(model.serviceName)", role: .destructive) {
                Task {
                    if await model.discard() { onClose(nil) }
                }
            }
        } message: {
            Text(
                "Coolify created it in \(place) a moment ago. Keep it to set it up later, or delete it with its volumes."
            )
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            TemplateLogo(
                name: displayName,
                url: model.template?.logoURL(instanceRoot: model.instanceRoot),
                size: 56
            )
            VStack(alignment: .leading, spacing: 5) {
                Text(model.serviceName)
                    .font(.display(.title))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text("Created in \(place). Give it an address and fill in what it asks for, then start it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textCase(nil)
        .padding(.bottom, 14)
    }

    private func loadingRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private var startBar: some View {
        let missing = model.setup.missingKeys
        return HStack(spacing: 14) {
            FlameGlyph(heat: model.isSaving ? .warming : .cold, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.isSaving ? "Saving…" : "\(model.serviceName) is ready")
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.interpolate)
                Text(
                    missing.isEmpty
                        ? "Starting pulls its images and brings every container up."
                        : "Fill in \(ListFormatter.localizedString(byJoining: missing)) to start it."
                )
                .font(.caption)
                .foregroundStyle(missing.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.glow))
                .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button("Start Later") {
                Task {
                    if await model.save() { onClose(model.route) }
                }
            }
            .glassButton()
            .controlSize(.large)
            .disabled(isBusy)
            Button {
                Task { await model.start() }
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .glassButton(prominent: true)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(isBusy || model.isLoadingSetup || !missing.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
        .animation(.snappy, value: missing)
    }
}

/// A container's addresses, editable.
private struct DomainRow: View {
    @Binding var domain: DomainDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(domain.label)
                    .fontWeight(.medium)
                Spacer(minLength: 12)
                if let image = domain.image {
                    Text(verbatim: image)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            TextField("Address", text: $domain.value, prompt: Text(verbatim: "https://app.example.com"))
                .font(.body.monospaced())
                .labelsHidden()
                .textContentType(.URL)
                .autocorrectionDisabled()
                #if os(iOS)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
                #endif
        }
        .padding(.vertical, 2)
    }
}

/// A container with no public address, which can be given one.
private struct InternalContainerRow: View {
    var domain: DomainDraft
    var onAdd: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(domain.label)
                Text("Internal, reached by the other containers only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button("Add Address", systemImage: "plus", action: onAdd)
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderless)
        }
    }
}

/// One setting the template leaves to the user.
private struct SettingRow: View {
    @Binding var variable: VariableDraft

    private var isMissing: Bool {
        variable.isRequired && variable.value.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(verbatim: variable.key)
                    .font(.callout.monospaced().weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if variable.isRequired {
                    Text("Required")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isMissing ? AnyShapeStyle(.glow) : AnyShapeStyle(.secondary))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            isMissing ? AnyShapeStyle(.glow.opacity(0.15)) : AnyShapeStyle(.quaternary.opacity(0.7)),
                            in: .capsule)
                }
                Spacer(minLength: 0)
                if variable.isChanged {
                    Circle()
                        .fill(.ember)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel("Changed")
                }
            }
            field
        }
        .padding(.vertical, 2)
        .animation(.snappy, value: isMissing)
        .animation(.snappy, value: variable.isChanged)
    }

    @ViewBuilder
    private var field: some View {
        let prompt = Text(verbatim: variable.defaultValue.map { "Default: \($0)" } ?? "Empty")
        if variable.isHidden {
            Text("This token can't read its value. Change it later under Variables.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if variable.isSecret {
            SecureField(variable.key, text: $variable.value, prompt: prompt)
                .labelsHidden()
        } else {
            TextField(variable.key, text: $variable.value, prompt: prompt)
                .labelsHidden()
                .autocorrectionDisabled()
                #if os(iOS)
            .textInputAutocapitalization(.never)
                #endif
        }
    }
}

#Preview {
    let model = ProvisioningModel(
        placement: PlacementModel(
            projects: [
                Project(uuid: "p1", name: "Website", environments: [Environment(uuid: "e1", name: "production")])
            ],
            placement: Placement(projectUUID: "p1", environmentUUID: "e1")
        )
    )
    model.serviceName = "blog"
    model.setup = SetupDraft(
        domains: [
            DomainDraft(container: "ghost", label: "ghost", image: "ghost:5", original: "https://ghost-x1.example.com"),
            DomainDraft(container: "mysql", label: "mysql", image: "mysql:8.0", original: ""),
        ],
        settings: [
            VariableDraft(key: "MYSQL_DATABASE", original: "ghost", defaultValue: "ghost"),
            VariableDraft(key: "ADMIN_EMAIL", original: "", isRequired: true),
            VariableDraft(key: "MAIL_OPTIONS_AUTH_PASS", original: ""),
        ],
        generated: [
            VariableDraft(key: "SERVICE_PASSWORD_MYSQL", original: "x"),
            VariableDraft(key: "SERVICE_URL_GHOST", original: "https://ghost-x1.example.com"),
        ]
    )
    return NavigationStack {
        ServiceSetup(model: model) { _ in }
    }
    .frame(width: 720, height: 820)
}

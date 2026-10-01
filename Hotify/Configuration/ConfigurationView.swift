import CoolifyAPI
import SwiftUI

/// The Settings tab of a resource: its name and description, its domains, a database's public port, and its health
/// check, in one form with one Save. Nothing restarts or deploys on save. A bar offers that afterwards.
struct ConfigurationView: View {
    var model: ConfigurationModel
    var resource: ResourceSummary
    var pendingAction: ResourceAction?
    var onAction: (ResourceAction) -> Void

    private var draft: Binding<ResourceConfiguration> {
        Binding(
            get: { model.draft ?? ResourceConfiguration(kind: resource.kind, name: resource.name, description: "") },
            set: { model.draft = $0 }
        )
    }

    private var healthCheck: Binding<HealthCheck> {
        Binding(
            get: { model.draft?.healthCheck ?? HealthCheck() },
            set: { model.draft?.healthCheck = $0 }
        )
    }

    /// The action that puts saved changes to use. A stopped resource picks them up when it next starts.
    private var applyAction: ResourceAction? {
        guard resource.heat != .cold else { return nil }
        return resource.kind == .application ? .deploy : .restart
    }

    private var applyMessage: String {
        switch applyAction {
        case .deploy: "Saved. It takes effect after a redeploy."
        case .restart: "Saved. It takes effect after a restart."
        default: "Saved. It takes effect on the next start."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            notices
            content
        }
        .safeAreaInset(edge: .bottom) {
            if model.hasChanges {
                saveBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task(id: model.route) {
            await model.load()
        }
        .animation(.snappy, value: model.hasChanges)
        .animation(.snappy, value: model.hasUnappliedChanges)
        .animation(.snappy, value: model.saveError)
        .animation(.snappy, value: model.conflicts)
        .animation(.snappy, value: model.notice)
    }

    // MARK: States

    @ViewBuilder
    private var content: some View {
        if model.draft != nil {
            form
        } else if let loadError = model.loadError {
            ContentUnavailableView {
                Label("Settings didn't load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError)
            } actions: {
                Button("Try Again") {
                    Task { await model.load() }
                }
                .glassButton()
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var notices: some View {
        VStack(spacing: 8) {
            if model.hasUnappliedChanges {
                ApplyBar(
                    kind: resource.kind,
                    message: applyMessage,
                    action: applyAction,
                    isBusy: pendingAction != nil || resource.isDeploying,
                    onApply: { action in
                        onAction(action)
                        model.hasUnappliedChanges = false
                    },
                    onDismiss: { model.hasUnappliedChanges = false }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if !model.conflicts.isEmpty {
                ProblemNotice(problem: .conflicts(model.conflicts)) {
                    Task { await model.save(force: true) }
                }
            }
            if let saveError = model.saveError {
                NoticeBanner(message: saveError)
            }
            if let notice = model.notice {
                NoticeBanner(message: notice)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, hasNotices ? 12 : 0)
    }

    private var hasNotices: Bool {
        model.hasUnappliedChanges || !model.conflicts.isEmpty || model.saveError != nil || model.notice != nil
    }

    // MARK: Form

    private var form: some View {
        Form {
            Section("General") {
                TextField("Name", text: draft.name, prompt: Text("Name"))
                    .autocorrectionDisabled()
                TextField("Description", text: draft.description, prompt: Text("What it is for"), axis: .vertical)
                    .lineLimit(1...4)
            }

            switch resource.kind {
            case .application:
                if draft.wrappedValue.hasContainerDomains {
                    containerDomains(
                        empty:
                            "Coolify lists no service of this Docker Compose app with a domain yet. Give the first one a domain in Coolify, then edit them here."
                    )
                } else {
                    applicationDomains
                }
            case .service:
                containerDomains(empty: "None of this service's containers takes a domain.")
            case .database:
                publicAccess
            }

            if draft.wrappedValue.healthCheck != nil {
                HealthCheckSection(check: healthCheck, isApplication: resource.kind == .application)
            } else {
                Section("Health Check") {
                    Text("A service's health checks live in its compose file. Change them in Coolify.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(model.isSaving)
    }

    private var applicationDomains: some View {
        Section {
            DomainListEditor(domains: draft.domains, owner: resource.name)
            Picker("www", selection: draft.redirect) {
                Text("Answer on both").tag(DomainRedirect.both)
                Text("Redirect to www").tag(DomainRedirect.www)
                Text("Redirect to the bare domain").tag(DomainRedirect.nonWWW)
            }
            Toggle("Redirect HTTP to HTTPS", isOn: draft.forcesHTTPS)
        } header: {
            Text("Domains")
        } footer: {
            Text(
                draft.wrappedValue.domains.isEmpty
                    ? "Without a domain, the app is only reachable inside the server's network."
                    : "Coolify routes these to the app through the server's proxy. Changes take effect with the next deployment."
            )
        }
    }

    @ViewBuilder
    private func containerDomains(empty: String) -> some View {
        let containers = draft.containers
        if containers.wrappedValue.isEmpty {
            Section("Domains") {
                Text(empty)
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(containers) { container in
                Section {
                    DomainListEditor(domains: container.domains, owner: container.wrappedValue.label)
                } header: {
                    Text(container.wrappedValue.label)
                } footer: {
                    if container.wrappedValue.id == containers.wrappedValue.last?.id {
                        Text(
                            "Coolify routes each address to its container through the server's proxy. Changes take effect after a \(resource.kind == .application ? "redeploy" : "restart")."
                        )
                    }
                }
            }
        }
    }

    private var publicAccess: some View {
        Section {
            Toggle("Reachable from the internet", isOn: draft.isPublic)
            if draft.wrappedValue.isPublic {
                NumberField(title: "Public port", value: draft.publicPort, prompt: "5432")
            }
        } header: {
            Text("Public Access")
        } footer: {
            Text(
                draft.wrappedValue.isPublic
                    ? "Coolify forwards this port on the server to the database. Anyone who can reach the server can try to sign in, so keep its password strong."
                    : "Only resources on the server's network can reach the database."
            )
        }
    }

    // MARK: Saving

    private var saveBar: some View {
        let problem = model.draft?.problem
        return HStack(spacing: 12) {
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.glow)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Unsaved changes")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Revert") {
                model.revert()
            }
            .glassButton()
            .disabled(model.isSaving)
            Button {
                Task { await model.save() }
            } label: {
                if model.isSaving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Save")
                }
            }
            .glassButton(prominent: true)
            .disabled(problem != nil || model.isSaving)
            .keyboardShortcut("s", modifiers: .command)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}

#Preview("Application") {
    ConfigurationView(
        model: ConfigurationModel(
            saved: ResourceConfiguration(
                kind: .application,
                name: "marketing-site",
                description: "The public site",
                domains: ["https://hotify.example.com", "https://www.hotify.example.com"],
                redirect: .nonWWW,
                healthCheck: HealthCheck(
                    isEnabled: true, kind: .http, method: "GET", path: "/health", returnCode: 200, interval: 30)
            )
        ),
        resource: ResourceSummary(route: .application("web"), name: "marketing-site", status: "running:healthy"),
        onAction: { _ in }
    )
    .frame(width: 560, height: 820)
}

#Preview("Database") {
    ConfigurationView(
        model: ConfigurationModel(
            saved: ResourceConfiguration(
                kind: .database, name: "postgres", description: "",
                healthCheck: HealthCheck(isEnabled: true, interval: 15, timeout: 5, retries: 5, startPeriod: 5),
                isPublic: true, publicPort: 5433)
        ),
        resource: ResourceSummary(route: .database("pg"), name: "postgres", status: "running:healthy"),
        onAction: { _ in }
    )
    .frame(width: 560, height: 640)
}

#Preview("Service") {
    ConfigurationView(
        model: ConfigurationModel(
            saved: ResourceConfiguration(
                kind: .service, name: "metrics", description: "",
                containers: [
                    ContainerDomains(name: "grafana", label: "Grafana", domains: ["https://grafana.example.com"])
                ],
                hasContainerDomains: true)
        ),
        resource: ResourceSummary(route: .service("metrics"), name: "metrics", status: "running:healthy"),
        onAction: { _ in }
    )
    .frame(width: 560, height: 560)
}

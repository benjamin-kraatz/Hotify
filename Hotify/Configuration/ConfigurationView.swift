import CoolifyAPI
import SwiftUI

/// The Settings tab of a resource: its name and description, an application's source, a service's compose file, its
/// domains, a database's public port, its health check, an application's proxy labels and resource limits, and its
/// tags, in one form with one Save. The compose file is edited on a screen of its own, into the same draft and Save.
/// Nothing restarts or deploys on save. A bar offers that afterwards. Tags are saved on their own, as they are added or
/// removed.
struct ConfigurationView: View {
    var model: ConfigurationModel
    var resource: ResourceSummary
    var pendingAction: ResourceAction?
    var onAction: (ResourceAction) -> Void
    /// Opens a service's compose file in the editor. `nil` for anything else.
    var onEditCompose: (() -> Void)?
    @State private var tags: ResourceTagsModel

    init(
        model: ConfigurationModel,
        resource: ResourceSummary,
        pendingAction: ResourceAction? = nil,
        onAction: @escaping (ResourceAction) -> Void,
        onEditCompose: (() -> Void)? = nil,
        tags: ResourceTagsModel = ResourceTagsModel()
    ) {
        self.model = model
        self.resource = resource
        self.pendingAction = pendingAction
        self.onAction = onAction
        self.onEditCompose = onEditCompose
        _tags = State(initialValue: tags)
    }

    private var draft: Binding<ResourceConfiguration> {
        Binding(
            get: { model.draft ?? ResourceConfiguration(kind: resource.kind, name: resource.name, description: "") },
            set: { model.draft = $0 }
        )
    }

    private var source: Binding<ApplicationSource>? {
        guard let source = model.draft?.source else { return nil }
        return Binding(
            get: { model.draft?.source ?? source },
            set: { model.draft?.source = $0 }
        )
    }

    private var limits: Binding<ApplicationLimits>? {
        guard let limits = model.draft?.limits else { return nil }
        return Binding(
            get: { model.draft?.limits ?? limits },
            set: { model.draft?.limits = $0 }
        )
    }

    private var healthCheck: Binding<HealthCheck> {
        Binding(
            get: { model.draft?.healthCheck ?? HealthCheck() },
            set: { model.draft?.healthCheck = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ConfigurationNotices(model: model, resource: resource, pendingAction: pendingAction, onAction: onAction)
            content
        }
        .safeAreaInset(edge: .bottom) {
            if model.hasChanges {
                ConfigurationSaveBar(model: model)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task(id: model.route) {
            model.openTags(tags)
            await model.load()
            await tags.load()
        }
        .animation(.snappy, value: model.hasChanges)
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

    // MARK: Form

    private var form: some View {
        Form {
            Section("General") {
                TextField("Name", text: draft.name, prompt: Text("Name"))
                    .autocorrectionDisabled()
                TextField("Description", text: draft.description, prompt: Text("What it is for"), axis: .vertical)
                    .lineLimit(1...4)
            }

            if let source {
                SourceSection(source: source)
            }

            if resource.kind == .service {
                ComposeSection(compose: model.draft?.compose, isChanged: model.hasComposeChanges, onEdit: onEditCompose)
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
                LabelsSection(labels: draft.customLabels, escapesDollarSigns: draft.escapesDollarSigns)
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

            if let limits {
                LimitsSection(limits: limits)
            } else if resource.kind == .application {
                Section("Resources") {
                    Text("A Docker Compose app runs its compose file as written. Set its limits there.")
                        .foregroundStyle(.secondary)
                }
            }

            TagsSection(model: tags)
        }
        .formStyle(.grouped)
        .disabled(model.isSaving)
    }

    /// The domains alone in their section, then how the proxy redirects them in a section of its own.
    @ViewBuilder
    private var applicationDomains: some View {
        Section {
            DomainListEditor(domains: draft.domains, owner: resource.name)
        } header: {
            DomainSectionHeader(title: "Domains", domains: draft.domains, owner: resource.name)
        } footer: {
            Text(
                draft.wrappedValue.domains.isEmpty
                    ? "Without a domain, the app is only reachable inside the server's network."
                    : "Coolify routes these to the app through the server's proxy. Changes take effect with the next deployment."
            )
        }

        Section("Redirects") {
            Picker("www", selection: draft.redirect) {
                Text("Answer on both").tag(DomainRedirect.both)
                Text("Redirect to www").tag(DomainRedirect.www)
                Text("Redirect to the bare domain").tag(DomainRedirect.nonWWW)
            }
            Toggle("Redirect HTTP to HTTPS", isOn: draft.forcesHTTPS)
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
                    DomainSectionHeader(
                        title: container.wrappedValue.label, domains: container.domains,
                        owner: container.wrappedValue.label)
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
}

#Preview("Application") {
    ConfigurationView(
        model: ConfigurationModel(
            saved: ResourceConfiguration(
                kind: .application,
                name: "marketing-site",
                description: "The public site",
                source: ApplicationSource(kind: .image(name: "traefik/whoami"), tag: "v1.11.0"),
                domains: ["https://hotify.example.com", "https://www.hotify.example.com"],
                redirect: .nonWWW,
                healthCheck: HealthCheck(
                    isEnabled: true, kind: .http, method: "GET", path: "/health", returnCode: 200, interval: 30),
                limits: ApplicationLimits(limits: ResourceLimits(cpus: "1.5", memory: "512m")),
                customLabels: """
                    traefik.http.middlewares.hotify-compress.compress=true
                    traefik.http.routers.hotify.middlewares=hotify-compress
                    traefik.http.services.hotify.loadbalancer.server.port=3000
                    """,
                escapesDollarSigns: true
            )
        ),
        resource: ResourceSummary(
            route: .application("web"), name: "marketing-site", status: "running:healthy", tags: ["prod", "web"]),
        onAction: { _ in },
        tags: ResourceTagsModel(
            assigned: [Tag(uuid: "1", name: "prod"), Tag(uuid: "2", name: "web")],
            team: [
                Tag(uuid: "1", name: "prod"),
                Tag(uuid: "2", name: "web"),
                Tag(uuid: "3", name: "staging"),
            ]
        )
    )
    .frame(width: 560, height: 960)
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
                hasContainerDomains: true,
                compose: """
                    services:
                      grafana:
                        image: grafana/grafana-oss:11.2.0
                        environment:
                          - SERVICE_URL_GRAFANA_3000
                      prometheus:
                        image: prom/prometheus:v2.54.1
                    """)
        ),
        resource: ResourceSummary(route: .service("metrics"), name: "metrics", status: "running:healthy"),
        onAction: { _ in },
        onEditCompose: {}
    )
    .frame(width: 560, height: 720)
}

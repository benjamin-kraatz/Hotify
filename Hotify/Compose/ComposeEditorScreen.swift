import CoolifyAPI
import SwiftUI

/// A service's compose file on a screen of its own, in the detail column. It edits the Settings tab's draft, so going
/// back keeps the edits, and its Save is the Settings Save.
///
/// A compose file can hold passwords, so it stays behind the variable lock like the variables themselves.
struct ComposeEditorScreen: View {
    var model: ConfigurationModel
    var resource: ResourceSummary
    var pendingAction: ResourceAction?
    var onAction: (ResourceAction) -> Void

    /// Missing in previews, which show the file as it is.
    @SwiftUI.Environment(VariableLock.self) private var lock: VariableLock?
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isOpen: Bool { lock?.isOpen ?? true }

    private var compose: Binding<String> {
        Binding(
            get: { model.draft?.compose ?? "" },
            set: { model.setCompose($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 14)
            ConfigurationNotices(model: model, resource: resource, pendingAction: pendingAction, onAction: onAction)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .safeAreaInset(edge: .bottom) {
            if model.hasChanges {
                ConfigurationSaveBar(model: model)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task(id: model.route) {
            if model.draft == nil { await model.load() }
        }
        .animation(reduceMotion ? nil : .snappy, value: model.hasChanges)
        .animation(reduceMotion ? nil : .snappy, value: isOpen)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ComposeMark(size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(resource.name)
                    .font(.display(.title2))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(
                    "The compose file Coolify runs this service from. Saving keeps the running containers as they are until a restart."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        if let draft = model.draft {
            if draft.compose == nil {
                ContentUnavailableView {
                    Label("Coolify didn't send the compose file", systemImage: "eye.slash")
                } description: {
                    Text(
                        "Reading it takes a token with the root or read:sensitive permission, made by a team admin under Keys & Tokens. Paste it into Edit Instance in Hotify."
                    )
                }
            } else if !isOpen, let lock {
                LockCard(
                    method: lock.method,
                    failure: lock.failure,
                    isAuthenticating: lock.isAuthenticating,
                    title: "The compose file is locked",
                    prompt: "It can hold passwords. Confirm it’s you to see and change it."
                ) {
                    Task { await lock.unlock() }
                }
                .padding(.horizontal, 20)
                .transition(.opacity)
            } else {
                ComposeEditor(compose: compose, isEditable: !model.isSaving)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        } else if let loadError = model.loadError {
            ContentUnavailableView {
                Label("The compose file didn't load", systemImage: "exclamationmark.triangle")
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
}

#Preview("Editing") {
    let model = ConfigurationModel(
        saved: ResourceConfiguration(
            kind: .service, name: "metrics", description: "",
            compose: """
                services:
                  grafana:
                    image: grafana/grafana-oss:11.2.0
                    environment:
                      - SERVICE_URL_GRAFANA_3000
                      - GF_SECURITY_ADMIN_PASSWORD=${SERVICE_PASSWORD_GRAFANA}
                    volumes:
                      - grafana-data:/var/lib/grafana
                  prometheus:
                    image: prom/prometheus:v2.54.1
                volumes:
                  grafana-data: {}
                """
        )
    )
    model.draft?.compose = (model.draft?.compose ?? "") + "\n# A new line\n"
    return ComposeEditorScreen(
        model: model,
        resource: ResourceSummary(route: .service("metrics"), name: "metrics", status: "running:healthy"),
        onAction: { _ in }
    )
    .frame(width: 640, height: 640)
}

#Preview("Locked") {
    ComposeEditorScreen(
        model: ConfigurationModel(
            saved: ResourceConfiguration(kind: .service, name: "metrics", description: "", compose: "services: {}")
        ),
        resource: ResourceSummary(route: .service("metrics"), name: "metrics", status: "running:healthy"),
        onAction: { _ in }
    )
    .environment(VariableLock(isRequired: true))
    .frame(width: 640, height: 420)
}

#Preview("Hidden from the token") {
    ComposeEditorScreen(
        model: ConfigurationModel(saved: ResourceConfiguration(kind: .service, name: "metrics", description: "")),
        resource: ResourceSummary(route: .service("metrics"), name: "metrics", status: "exited"),
        onAction: { _ in }
    )
    .frame(width: 640, height: 420)
}

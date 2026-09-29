import SwiftUI

/// The top of the detail column: the flame, the name, where it lives, and the actions that fit its state.
struct ResourceHeader: View {
    var resource: ResourceSummary
    var pendingAction: ResourceAction?
    /// The newest production deployment failed. With the app stopped, that is why.
    var lastDeploymentFailed = false
    var onAction: (ResourceAction) -> Void

    private var hasFailed: Bool {
        pendingAction == nil && !resource.isDeploying && resource.heat == .cold && lastDeploymentFailed
    }

    private var heat: Heat {
        hasFailed ? .troubled : resource.heat(pendingAction: pendingAction)
    }

    private var statusText: String {
        hasFailed ? "Deployment failed" : StatusLabel.text(for: resource, pendingAction: pendingAction)
    }

    private var actions: [ResourceAction] {
        ResourceAction.available(for: resource)
    }

    /// One line on what is happening, or on what the buttons do. Start and Redeploy read alike otherwise.
    private var caption: String? {
        let isApplication = resource.kind == .application
        switch pendingAction {
        case .start?:
            return isApplication
                ? "Coolify is building the latest commit, then starts it. Deployments shows the progress."
                : "Coolify is starting the containers."
        case .deploy?:
            return "Coolify is building the latest commit. Deployments shows the progress."
        case .restart?:
            return "Coolify is restarting the containers."
        case .stop?:
            return "Coolify is stopping the containers."
        case .cancelDeployment?:
            return "Coolify is cancelling the deployment."
        case nil:
            break
        }
        if resource.isDeploying {
            return "A deployment is running. Deployments shows the progress."
        }
        guard isApplication else { return nil }
        if hasFailed {
            return "Check Deployments for what went wrong. Start tries again with the latest commit."
        }
        switch resource.heat {
        case .cold: return "Start builds the latest commit and runs it."
        case .lit, .warming, .troubled: return "Redeploy builds the latest commit. Restart keeps the current build."
        case .unknown: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 18) {
                FlameGlyph(heat: heat, height: 56, ignitesOnAppear: true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(resource.name)
                        .font(.display(.title))
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .textSelection(.enabled)

                    HStack(spacing: 12) {
                        Label(resource.kind.title, systemImage: resource.kind.systemImage)
                            .foregroundStyle(.secondary)
                        Text(statusText)
                            .fontWeight(.semibold)
                            .foregroundStyle(heat.tint)
                            .contentTransition(.interpolate)
                    }
                    .font(.subheadline)

                    if let place = resource.place {
                        Text(
                            place.environmentName.isEmpty
                                ? place.projectName : "\(place.projectName) · \(place.environmentName)"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }

                    if let link = resource.link {
                        Link(destination: link) {
                            Label(link.host() ?? link.absoluteString, systemImage: "arrow.up.right")
                                .labelStyle(TrailingIconLabelStyle())
                        }
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                    }
                }
            }

            if !actions.isEmpty || caption != nil {
                VStack(alignment: .leading, spacing: 8) {
                    actionBar
                    if let caption {
                        Text(caption)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.opacity)
                    }
                }
            }
        }
        .animation(.snappy, value: heat)
        .animation(.snappy, value: statusText)
        .animation(.snappy, value: actions)
        .animation(.snappy, value: caption)
    }

    private var actionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                buttons
            }
            VStack(alignment: .leading, spacing: 10) {
                buttons
            }
        }
        .controlSize(.large)
        .labelStyle(.titleAndIcon)
    }

    private var buttons: some View {
        ForEach(actions) { action in
            Button(action.title, systemImage: action.systemImage) {
                onAction(action)
            }
            // The first action is the likely one, unless it takes the resource down.
            .glassButton(prominent: action == actions.first && action != .stop && action != .cancelDeployment)
            .disabled(action.isBlocked(by: pendingAction))
            .help(action.explanation(for: resource.kind))
            .accessibilityHint(action.explanation(for: resource.kind))
            .keyboardShortcut(action.shortcut)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }
}

extension ResourceAction {
    /// Shortcuts for the actions that do not take anything down.
    fileprivate var shortcut: KeyboardShortcut? {
        switch self {
        case .start: KeyboardShortcut("s", modifiers: [.command, .shift])
        case .deploy: KeyboardShortcut("d", modifiers: [.command, .shift])
        case .restart: KeyboardShortcut("r", modifiers: [.command, .shift])
        case .stop, .cancelDeployment: nil
        }
    }
}

/// Title first, then the icon, for links that leave the app.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
                .imageScale(.small)
        }
    }
}

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 40) {
            ResourceHeader(
                resource: ResourceSummary(
                    route: .application("web"),
                    name: "marketing-site",
                    status: "running:healthy",
                    link: URL(string: "https://hotify.example.com"),
                    place: ResourcePlace(projectName: "Website", environmentName: "production", environmentID: 1)
                ),
                onAction: { _ in }
            )
            ResourceHeader(
                resource: ResourceSummary(route: .application("api"), name: "api", status: "exited"),
                lastDeploymentFailed: true,
                onAction: { _ in }
            )
            ResourceHeader(
                resource: ResourceSummary(route: .application("docs"), name: "docs", status: "exited"),
                pendingAction: .start,
                onAction: { _ in }
            )
            ResourceHeader(
                resource: ResourceSummary(route: .database("pg"), name: "postgres", status: "exited"),
                onAction: { _ in }
            )
        }
        .padding(24)
    }
}

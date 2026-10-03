import SwiftUI

/// The top of the detail column: the flame, the name, where it lives, and the actions that fit its state.
struct ResourceHeader: View {
    var resource: ResourceSummary
    var pendingAction: ResourceAction?
    /// The newest production deployment failed. With the app stopped, that is why.
    var lastDeploymentFailed = false
    /// Opens the project the resource lives in. `nil` leaves its place as plain text.
    var onOpenProject: (() -> Void)?
    /// Opens the settings that hold an application's pinned commit. `nil` shows the pin as plain text.
    var onShowSource: (() -> Void)?
    var onAction: (ResourceAction) -> Void

    @SwiftUI.Environment(\.placePalette) private var palette

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
                        if let pin = resource.pinnedCommit {
                            pinTag(pin)
                        }
                    }
                    .font(.subheadline)

                    if let place = resource.place {
                        placeLine(place)
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

            if !actions.isEmpty {
                actionBar
            }
        }
        .animation(.snappy, value: heat)
        .animation(.snappy, value: statusText)
        .animation(.snappy, value: actions)
    }

    /// Says that manual deploys build one commit, not the branch's latest. A pin isn't a problem, so it gets no heat.
    @ViewBuilder
    private func pinTag(_ pin: String) -> some View {
        let tag = Tag(text: "Pinned to \(pin)")
        if let onShowSource {
            Button(action: onShowSource) { tag }
                .buttonStyle(.plain)
                .help("Redeploy builds \(pin), not the branch's latest. Change it in Settings.")
                .accessibilityHint("Shows the source settings")
        } else {
            tag
        }
    }

    /// The project and environment, each after its color. With somewhere to go, it is the way up to the project's
    /// page.
    @ViewBuilder
    private func placeLine(_ place: ResourcePlace) -> some View {
        let text =
            place.environmentName.isEmpty ? place.projectName : "\(place.projectName) · \(place.environmentName)"
        let names = placeNames(place)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
        if let onOpenProject {
            Button(action: onOpenProject) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    names
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .help("Show the \(place.projectName) project")
            .accessibilityHint("Shows the project")
        } else {
            names
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func placeNames(_ place: ResourcePlace) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            PlaceMark(tint: palette.project(place.projectID))
            Text(place.projectName)
            if !place.environmentName.isEmpty {
                Text(verbatim: "·")
                PlaceMark(tint: palette.environment(place.environmentUUID))
                Text(place.environmentName)
            }
        }
    }

    /// Every label when they fit. Then the lead action keeps its label and the rest shrink to icons,
    /// and on the narrowest screens the rest move into a menu.
    private var actionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                ForEach(actions) { action in
                    button(action, showsTitle: true)
                }
            }
            HStack(spacing: 10) {
                ForEach(actions) { action in
                    button(action, showsTitle: action == actions.first)
                }
            }
            HStack(spacing: 10) {
                if let lead = actions.first {
                    button(lead, showsTitle: true)
                }
                moreMenu
            }
        }
        .controlSize(.large)
    }

    private func button(_ action: ResourceAction, showsTitle: Bool) -> some View {
        Button(action.title, systemImage: action.systemImage) {
            onAction(action)
        }
        .labelStyle(ActionLabelStyle(showsTitle: showsTitle))
        // The first action is the likely one, unless it takes the resource down.
        .glassButton(prominent: action == actions.first && action != .stop && action != .cancelDeployment)
        .disabled(action.isBlocked(by: pendingAction))
        .help(action.explanation(for: resource.kind))
        .accessibilityHint(action.explanation(for: resource.kind))
        .keyboardShortcut(action.shortcut)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    @ViewBuilder
    private var moreMenu: some View {
        let rest = actions.dropFirst()
        if !rest.isEmpty {
            Menu {
                ForEach(Array(rest)) { action in
                    Button(action == .stop ? "Stop…" : action.title, systemImage: action.systemImage) {
                        onAction(action)
                    }
                    .disabled(action.isBlocked(by: pendingAction))
                }
            } label: {
                Label("More Actions", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
            }
            .menuIndicator(.hidden)
            .glassButton()
        }
    }
}

/// Title and icon, or the icon alone while the title still reaches VoiceOver.
private struct ActionLabelStyle: LabelStyle {
    var showsTitle: Bool

    func makeBody(configuration: Configuration) -> some View {
        if showsTitle {
            Label(configuration)
                .labelStyle(.titleAndIcon)
        } else {
            Label(configuration)
                .labelStyle(.iconOnly)
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
                    place: ResourcePlace(
                        projectID: "website", projectName: "Website", environmentName: "production",
                        environmentID: 1, environmentUUID: "env-prod"),
                    pinnedCommit: "528a020"
                ),
                onOpenProject: {},
                onShowSource: {},
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
    .environment(\.placePalette, .preview(projects: ["website": .teal], environments: ["env-prod": .orange]))
}

import SwiftUI

/// The top of the detail column: the flame, the name, its state, where it lives, and its address. The actions sit in
/// the toolbar.
struct ResourceHeader: View {
    var resource: ResourceSummary
    var pendingAction: ResourceAction?
    /// The newest production deployment failed. With the app stopped, that is why.
    var lastDeploymentFailed = false
    /// Opens the project the resource lives in. `nil` leaves its place as plain text.
    var onOpenProject: (() -> Void)?
    /// Opens the settings that hold an application's pinned commit. `nil` shows the pin as plain text.
    var onShowSource: (() -> Void)?

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

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            FlameGlyph(heat: heat, height: 46, ignitesOnAppear: true)

            VStack(alignment: .leading, spacing: 5) {
                Text(resource.name)
                    .font(.display(.title2))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    Text(statusText)
                        .fontWeight(.semibold)
                        .foregroundStyle(heat.tint)
                        .contentTransition(.interpolate)
                    separator
                    Label(resource.kind.title, systemImage: resource.kind.systemImage)
                        .foregroundStyle(.secondary)
                    if let pin = resource.pinnedCommit {
                        pinTag(pin)
                    }
                }
                .font(.subheadline)
                .lineLimit(1)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        placeAndLink(separated: true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        placeAndLink(separated: false)
                    }
                }
            }
        }
        .animation(.snappy, value: heat)
        .animation(.snappy, value: statusText)
    }

    private var separator: some View {
        Text(verbatim: "·")
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func placeAndLink(separated: Bool) -> some View {
        if let place = resource.place {
            placeLine(place)
        }
        if let link = resource.link {
            if separated, resource.place != nil {
                separator
                    .font(.subheadline)
            }
            Link(destination: link) {
                Label(link.host() ?? link.absoluteString, systemImage: "arrow.up.right")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .font(.subheadline)
            .foregroundStyle(.tint)
            .lineLimit(1)
        }
    }

    /// Says that manual deploys build one commit, not the branch's latest. A pin isn't a problem, so it gets no heat.
    @ViewBuilder
    private func pinTag(_ pin: String) -> some View {
        let tag = Chip(text: "Pinned to \(pin)")
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
                onShowSource: {}
            )
            ResourceHeader(
                resource: ResourceSummary(route: .application("api"), name: "api", status: "exited"),
                lastDeploymentFailed: true
            )
            ResourceHeader(
                resource: ResourceSummary(route: .application("docs"), name: "docs", status: "exited"),
                pendingAction: .start
            )
            ResourceHeader(
                resource: ResourceSummary(route: .database("pg"), name: "postgres", status: "exited")
            )
        }
        .padding(24)
    }
    .environment(\.placePalette, .preview(projects: ["website": .teal], environments: ["env-prod": .orange]))
}

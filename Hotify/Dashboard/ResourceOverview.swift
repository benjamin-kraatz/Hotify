import SwiftUI

/// The first tab of a resource: a card for each part of it that has something to say, such as its containers, its
/// latest deployments, the end of its logs, and its variables. Each card leads to the tab that holds the rest.
struct ResourceOverview: View {
    var resource: ResourceSummary
    var deployments: [DeploymentLine]
    var logLines: [LogLine]
    /// Why there are no logs, when the resource or its container is stopped.
    var pausedMessage: String?
    var variables: VariablesModel
    var onOpen: (DetailTab) -> Void
    var onSelectDeployment: (DeploymentLine) -> Void

    /// The natural height of the tallest card, which every card stretches to.
    @State private var cardHeight: CGFloat?

    private var recentDeployments: [DeploymentLine] {
        Array(deployments.filter { !$0.isPreview }.prefix(3))
    }

    private var lastLines: [LogLine] {
        Array(logLines.suffix(5))
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)], spacing: 16) {
                if resource.kind == .service, !resource.containers.isEmpty {
                    containers
                }
                if resource.kind == .application {
                    deploymentsCard
                }
                logs
                variablesCard
            }
            .padding(24)
            .onPreferenceChange(OverviewCardHeight.self) { cardHeight = $0 }
            .environment(\.overviewCardHeight, cardHeight)
        }
    }

    // MARK: Cards

    private var containers: some View {
        OverviewCard(title: "Containers", destination: .containers, onOpen: onOpen) {
            VStack(spacing: 10) {
                ForEach(resource.containers) { container in
                    HStack(spacing: 12) {
                        FlameGlyph(heat: container.heat, height: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(container.name)
                                .fontWeight(.medium)
                            if let image = container.image {
                                Text(image)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(StatusLabel.text(for: container.status))
                            .font(.caption)
                            .foregroundStyle(container.heat.tint)
                    }
                }
            }
        }
    }

    private var deploymentsCard: some View {
        OverviewCard(title: "Deployments", destination: .deployments, onOpen: onOpen) {
            if recentDeployments.isEmpty {
                placeholder("Nothing deployed yet.")
            } else {
                VStack(spacing: 4) {
                    ForEach(recentDeployments) { deployment in
                        Button {
                            onSelectDeployment(deployment)
                        } label: {
                            deploymentRow(deployment)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func deploymentRow(_ deployment: DeploymentLine) -> some View {
        HStack(spacing: 12) {
            FlameGlyph(heat: deployment.heat, height: 18, tone: deployment.tone)
            VStack(alignment: .leading, spacing: 2) {
                Text(deployment.message ?? deployment.commit ?? deployment.statusLabel)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(deployment.statusLabel)
                        .foregroundStyle(deployment.heat == .cold ? .secondary : deployment.heat.tint)
                    if let commit = deployment.commit {
                        Text(commit)
                            .monospaced()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let startedAt = deployment.startedAt {
                Text(startedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }

    private var logs: some View {
        OverviewCard(title: "Latest Logs", destination: .logs, onOpen: onOpen) {
            if let pausedMessage, lastLines.isEmpty {
                placeholder(pausedMessage)
            } else if lastLines.isEmpty {
                placeholder("No output yet.")
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(lastLines) { line in
                        Text(line.text)
                            .foregroundStyle(line.isAlarming ? AnyShapeStyle(.glow) : AnyShapeStyle(.primary))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .font(.caption.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .well(cornerRadius: 9)
            }
        }
    }

    /// Keys only. Their values stay behind the lock on the Variables tab.
    private var variablesCard: some View {
        OverviewCard(title: "Variables", destination: .variables, onOpen: onOpen) {
            let production = variables.variables.filter { !$0.isPreview }
            if !variables.hasLoaded {
                placeholder(variables.loadError ?? "Loading…")
            } else if production.isEmpty {
                placeholder("No variables yet.")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(production.prefix(4)) { variable in
                        Text(variable.key)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                    }
                    Label(
                        production.count == 1
                            ? "1 variable, value locked" : "\(production.count) variables, values locked",
                        systemImage: "lock"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One card of the overview: a title, a way to the tab it sums up, and what it shows.
private struct OverviewCard<Content: View>: View {
    var title: String
    var destination: DetailTab
    var onOpen: (DetailTab) -> Void
    @ViewBuilder var content: Content

    @SwiftUI.Environment(\.overviewCardHeight) private var height

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open \(destination.title)") {
                    onOpen(destination)
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.tint)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Measured before the stretch below, so a card that shrinks lets the others shrink with it.
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: OverviewCardHeight.self, value: proxy.size.height)
            }
        }
        .frame(minHeight: height, alignment: .top)
        .well()
    }
}

/// The tallest natural height among the overview's cards.
private struct OverviewCardHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension EnvironmentValues {
    /// The height every overview card stretches to, so they line up.
    @Entry fileprivate var overviewCardHeight: CGFloat?
}

#Preview("Service") {
    ResourceOverview(
        resource: ResourceSummary(
            route: .service("wp"),
            name: "homepage-maike",
            status: "exited",
            containers: [
                ContainerSummary(id: 1, name: "wordpress", status: "exited", image: "wordpress:6.6-apache"),
                ContainerSummary(id: 2, name: "mariadb", status: "exited", image: "mariadb:11.4"),
            ]
        ),
        deployments: [],
        logLines: [],
        pausedMessage: "wordpress isn't running. Start the service to read its output.",
        variables: VariablesModel(),
        onOpen: { _ in },
        onSelectDeployment: { _ in }
    )
    .frame(width: 720, height: 520)
}

#Preview("Application") {
    ResourceOverview(
        resource: ResourceSummary(route: .application("web"), name: "checkout-app", status: "running:healthy"),
        deployments: [
            DeploymentLine(
                id: "1", status: "finished", commit: "4f2a91c", message: "fix: cart totals",
                startedAt: .now.addingTimeInterval(-3600)),
            DeploymentLine(
                id: "2", status: "failed", commit: "9c01d2e", message: "feat: gift cards",
                startedAt: .now.addingTimeInterval(-86_400)),
        ],
        logLines: LogLine.parse("2026-10-17T14:02:01Z GET / 200\n2026-10-17T14:02:04Z warn slow query"),
        variables: VariablesModel(),
        onOpen: { _ in },
        onSelectDeployment: { _ in }
    )
    .frame(width: 720, height: 520)
}

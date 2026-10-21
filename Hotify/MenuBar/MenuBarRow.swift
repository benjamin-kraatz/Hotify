#if os(macOS)
import SwiftUI

/// One watched resource, laid out like its row in the dashboard, with its latest deployment under it.
struct MenuBarRow: View {
    var entry: WatchedResource
    var state: MenuBarResourceState
    var onOpen: () -> Void
    var onAction: (ResourceAction) -> Void

    @State private var isHovered = false

    private var kind: ResourceKind? { entry.route?.kind }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                FlameGlyph(heat: state.heat, height: 17)
                    .frame(width: 16)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(state.resource?.name ?? entry.name)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(state.statusText)
                            .font(.subheadline)
                            .foregroundStyle(
                                state.heat.needsAttention || state.isStale
                                    ? AnyShapeStyle(.glow) : AnyShapeStyle(.secondary)
                            )
                            .contentTransition(.interpolate)
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        if let kind {
                            Image(systemName: kind.systemImage)
                                .imageScale(.small)
                                .accessibilityLabel(kind.title)
                        }
                        Text(state.resource?.subtitle ?? kind?.title ?? "")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    if let deployment = state.latestDeployment {
                        MenuBarDeploymentLine(deployment: deployment)
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(isHovered ? 0.07 : 0), in: .rect(cornerRadius: 9))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.15), value: isHovered)
        .animation(.snappy, value: state.statusText)
        .animation(.snappy, value: state.latestDeployment)
        .help("Open \(entry.name) in Hotify")
        .accessibilityElement(children: .combine)
        .accessibilityValue(state.statusText)
        .contextMenu { menu }
    }

    /// Where to go first, then what to do to the resource.
    @ViewBuilder
    private var menu: some View {
        Button("Open in Hotify", systemImage: "macwindow", action: onOpen)
        if let link = state.resource?.link {
            Link(destination: link) {
                Label("Open \(link.host() ?? link.absoluteString)", systemImage: "safari")
            }
        }
        Divider()
        let available = state.resource.map(ResourceAction.available(for:)) ?? []
        ForEach([ResourceAction.restart, .stop]) { action in
            // Stop asks first, so it carries an ellipsis.
            Button(action == .stop ? "Stop…" : action.title, systemImage: action.systemImage) {
                onAction(action)
            }
            .help(kind.map { action.explanation(for: $0) } ?? "")
            .disabled(!available.contains(action) || action.isBlocked(by: state.pendingAction))
        }
    }
}

/// How the newest production deployment went, and when.
private struct MenuBarDeploymentLine: View {
    var deployment: DeploymentLine

    private var isUnderway: Bool { DeploymentStatus.isUnderway(deployment.status) }

    private var systemImage: String {
        switch deployment.status {
        case "in_progress": "hammer"
        case "queued": "clock"
        case "finished": "checkmark.circle"
        case "failed": "exclamationmark.triangle"
        default: "xmark.circle"
        }
    }

    /// Since when a deployment runs, or when it ended.
    private var time: Text? {
        let date = isUnderway ? deployment.startedAt : (deployment.finishedAt ?? deployment.startedAt)
        return date.map { Text($0, format: .relative(presentation: .named)) }
    }

    private var label: Text {
        let status = Text(deployment.statusLabel)
        guard let time else { return status }
        return isUnderway ? Text("\(status), started \(time)") : Text("\(status) \(time)")
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .symbolEffect(.pulse, isActive: isUnderway)
            if let commit = deployment.commit {
                Text("\(label) · \(Text(commit).monospaced())")
            } else {
                label
            }
        }
        .lineLimit(1)
        .font(.subheadline)
        .foregroundStyle(deployment.heat.needsAttention ? AnyShapeStyle(.glow) : AnyShapeStyle(.secondary))
        .help(deployment.message ?? "")
    }
}

#Preview {
    let summary = ResourceSummary(
        route: .application("a1"),
        name: "checkout-app",
        status: "running:healthy",
        subtitle: "checkout.example.com",
        link: URL(string: "https://checkout.example.com"),
        isDeploying: true
    )
    let failed = ResourceSummary(
        route: .application("a2"),
        name: "admin-platform",
        status: "running:healthy",
        subtitle: "admin.example.com",
        link: URL(string: "https://admin.example.com")
    )
    let entry = WatchedResource(instanceID: UUID(), instanceName: "Home", resource: summary)
    VStack(spacing: 2) {
        MenuBarRow(
            entry: entry,
            state: MenuBarResourceState(
                resource: summary,
                latestDeployment: DeploymentLine(
                    id: "1", status: "in_progress", commit: "a1b2c3d", startedAt: .now.addingTimeInterval(-95)),
                updatedAt: .now
            ),
            onOpen: {},
            onAction: { _ in }
        )
        MenuBarRow(
            entry: WatchedResource(instanceID: entry.instanceID, instanceName: "Home", resource: failed),
            state: MenuBarResourceState(
                resource: failed,
                latestDeployment: DeploymentLine(
                    id: "2", status: "failed", commit: "9f8e7d6", finishedAt: .now.addingTimeInterval(-3_600)),
                updatedAt: .now
            ),
            onOpen: {},
            onAction: { _ in }
        )
    }
    .padding(6)
    .frame(width: 340)
}
#endif

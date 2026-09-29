import SwiftUI

/// The top of the detail column: the flame, the name, what it is, and the actions that fit its state.
struct ResourceHeader: View {
    var resource: ResourceSummary
    var pendingAction: ResourceAction?
    var isDeploying: Bool
    var onAction: (ResourceAction) -> Void
    var onDeploy: () -> Void

    private var heat: Heat {
        pendingAction == nil ? resource.heat : .warming
    }

    private var statusText: String {
        pendingAction.map { StatusLabel.text(for: $0) } ?? StatusLabel.text(for: resource.status)
    }

    private var statusStyle: AnyShapeStyle {
        switch heat {
        case .lit: AnyShapeStyle(.ember)
        case .warming, .troubled: AnyShapeStyle(.glow)
        case .cold, .unknown: AnyShapeStyle(.secondary)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
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
                            .foregroundStyle(statusStyle)
                            .contentTransition(.interpolate)
                    }
                    .font(.subheadline)

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

            actionBar
        }
        .animation(.snappy, value: heat)
        .animation(.snappy, value: statusText)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if resource.kind == .application {
                Button(action: onDeploy) {
                    Label(isDeploying ? "Deploying…" : "Deploy", systemImage: "arrow.up.circle.fill")
                        .symbolEffect(.pulse, isActive: isDeploying)
                        .contentTransition(.interpolate)
                }
                .glassButton(prominent: true)
                .disabled(isDeploying)
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }

            Group {
                if heat == .cold || heat == .unknown {
                    actionButton(.start, prominent: resource.kind != .application)
                }
                if heat != .cold {
                    actionButton(.restart, prominent: false)
                    actionButton(.stop, prominent: false)
                }
            }
            .disabled(pendingAction != nil)
        }
        .controlSize(.large)
        .labelStyle(.titleAndIcon)
    }

    private func actionButton(_ action: ResourceAction, prominent: Bool) -> some View {
        Button(action.title, systemImage: action.systemImage) {
            onAction(action)
        }
        .glassButton(prominent: prominent)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
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
    VStack(alignment: .leading, spacing: 40) {
        ResourceHeader(
            resource: ResourceSummary(
                route: .application("web"),
                name: "marketing-site",
                status: "running:healthy",
                link: URL(string: "https://hotify.example.com")
            ),
            pendingAction: nil,
            isDeploying: false,
            onAction: { _ in },
            onDeploy: {}
        )
        ResourceHeader(
            resource: ResourceSummary(route: .database("pg"), name: "postgres", status: "exited"),
            pendingAction: nil,
            isDeploying: false,
            onAction: { _ in },
            onDeploy: {}
        )
    }
    .padding(24)
}

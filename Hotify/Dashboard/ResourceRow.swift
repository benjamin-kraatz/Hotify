import SwiftUI

/// One application, database, or service in the dashboard list.
struct ResourceRow: View {
    var resource: ResourceSummary
    var pendingAction: ResourceAction?

    private var heat: Heat {
        pendingAction == nil ? resource.heat : .warming
    }

    private var statusText: String {
        pendingAction.map { StatusLabel.text(for: $0) } ?? StatusLabel.text(for: resource.status)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FlameGlyph(heat: heat, height: 17)
                .frame(width: 16)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(resource.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(heat.needsAttention ? AnyShapeStyle(.glow) : AnyShapeStyle(.secondary))
                        .contentTransition(.interpolate)
                        .lineLimit(1)
                }
                if resource.subtitle != nil || !resource.containers.isEmpty {
                    HStack(spacing: 8) {
                        if !resource.containers.isEmpty {
                            HeatStrip(heats: resource.containers.map(\.heat), tickWidth: 4, height: 7)
                                .fixedSize()
                        }
                        if let subtitle = resource.subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 5)
        .animation(.snappy, value: statusText)
        .accessibilityElement(children: .combine)
        .accessibilityValue(statusText)
    }
}

#Preview {
    List {
        ResourceRow(
            resource: ResourceSummary(
                route: .application("web"),
                name: "marketing-site",
                status: "running:healthy",
                subtitle: "hotify.example.com"
            )
        )
        ResourceRow(
            resource: ResourceSummary(
                route: .service("convex"),
                name: "convex",
                status: "running:healthy",
                subtitle: "2 containers",
                containers: [
                    ContainerSummary(id: 1, name: "dashboard", status: "running:healthy"),
                    ContainerSummary(id: 2, name: "backend", status: "running:healthy"),
                ]
            ),
            pendingAction: .restart
        )
        ResourceRow(
            resource: ResourceSummary(route: .database("pg"), name: "postgres", status: "exited")
        )
        ResourceRow(
            resource: ResourceSummary(route: .database("redis"), name: "redis", status: "running:unhealthy")
        )
    }
}

import SwiftUI

/// One application, database, or service in the dashboard list.
struct ResourceRow: View {
    var resource: ResourceSummary
    var pendingAction: ResourceAction?

    private var heat: Heat {
        resource.heat(pendingAction: pendingAction)
    }

    private var statusText: String {
        StatusLabel.text(for: resource, pendingAction: pendingAction)
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
                // Sections group by project, so the kind rides along on every row.
                HStack(spacing: 8) {
                    Image(systemName: resource.kind.systemImage)
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(resource.kind.title)
                    if !resource.containers.isEmpty {
                        HeatStrip(heats: resource.containers.map(\.heat), tickWidth: 4, height: 7)
                            .fixedSize()
                    }
                    Text(resource.subtitle ?? resource.kind.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
            resource: ResourceSummary(
                route: .database("pg"), name: "postgres", status: "exited", subtitle: "PostgreSQL")
        )
        ResourceRow(
            resource: ResourceSummary(
                route: .application("api"),
                name: "api",
                status: "exited",
                subtitle: "example/api",
                isDeploying: true
            )
        )
        ResourceRow(
            resource: ResourceSummary(route: .database("redis"), name: "redis", status: "running:unhealthy")
        )
    }
}

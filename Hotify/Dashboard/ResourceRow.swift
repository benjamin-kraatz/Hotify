import SwiftUI

/// One application, database, or service in the dashboard list.
struct ResourceRow: View {
    var resource: ResourceSummary
    var pendingAction: ResourceAction?
    /// Puts the status beside both lines, at their middle, rather than on the name's line. For a row that ends in
    /// a chevron, which sits at the middle too.
    var centersStatus = false

    private var heat: Heat {
        resource.heat(pendingAction: pendingAction)
    }

    private var statusText: String {
        StatusLabel.text(for: resource, pendingAction: pendingAction)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            lines
            if centersStatus {
                Spacer(minLength: 0)
                status
            }
        }
        .padding(.vertical, 5)
        .animation(.snappy, value: statusText)
        .animation(.snappy, value: resource.buildingPreviews)
        .accessibilityElement(children: .combine)
        .accessibilityValue(statusText)
    }

    private var status: some View {
        Text(statusText)
            .font(.subheadline)
            .foregroundStyle(heat.needsAttention ? AnyShapeStyle(.glow) : AnyShapeStyle(.secondary))
            .contentTransition(.interpolate)
            .lineLimit(1)
    }

    private var lines: some View {
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
                    if !centersStatus {
                        Spacer(minLength: 8)
                        status
                    }
                }
                // Sections group by project, so the kind rides along on every row.
                HStack(spacing: 8) {
                    Image(systemName: resource.kind.systemImage)
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(resource.kind.title)
                    if let first = resource.buildingPreviews.first {
                        BuildingPreviewMark(first: first, count: resource.buildingPreviews.count)
                    }
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
    }
}

/// A blue flame beside the row while a pull request preview builds, with the PR it is building.
private struct BuildingPreviewMark: View {
    var first: Int
    var count: Int

    @SwiftUI.Environment(\.backgroundProminence) private var prominence

    var body: some View {
        HStack(spacing: 3) {
            FlameGlyph(heat: .warming, height: 11, tone: .preview)
            Text(verbatim: count > 1 ? "#\(first) +\(count - 1)" : "#\(first)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(prominence == .increased ? AnyShapeStyle(.white) : AnyShapeStyle(.pilot))
        .fixedSize()
        .transition(.scale(scale: 0.6).combined(with: .opacity))
        .accessibilityElement()
        .accessibilityLabel(
            count > 1 ? "Building \(count) previews" : "Building the preview of pull request \(first)")
    }
}

#Preview {
    List {
        ResourceRow(
            resource: ResourceSummary(
                route: .application("web"),
                name: "marketing-site",
                status: "running:healthy",
                subtitle: "hotify.example.com",
                buildingPreviews: [42]
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

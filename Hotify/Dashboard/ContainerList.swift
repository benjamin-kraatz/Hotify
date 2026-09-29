import SwiftUI

/// The containers inside a service, each with its own status.
struct ContainerList: View {
    var containers: [ContainerSummary]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(containers.enumerated()), id: \.element.id) { index, container in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 46)
                    }
                    ContainerRow(container: container)
                }
            }
            .background(Color.primary.opacity(0.045), in: .rect(cornerRadius: 14))
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .overlay {
            if containers.isEmpty {
                ContentUnavailableView(
                    "No containers",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("Coolify lists no containers for this service.")
                )
            }
        }
        .animation(.snappy, value: containers)
    }
}

private struct ContainerRow: View {
    var container: ContainerSummary

    var body: some View {
        HStack(spacing: 14) {
            FlameGlyph(heat: container.heat, height: 18)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(container.name)
                    .font(.body.weight(.semibold))
                if let image = container.image, !image.isEmpty {
                    Text(image)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if let link = container.link {
                Link(destination: link) {
                    Image(systemName: "arrow.up.right.square")
                }
                .foregroundStyle(.secondary)
                .help("Open \(link.host() ?? link.absoluteString)")
                .accessibilityLabel("Open \(link.host() ?? link.absoluteString)")
            }
            Text(StatusLabel.text(for: container.status))
                .font(.subheadline)
                .foregroundStyle(container.heat.needsAttention ? AnyShapeStyle(.glow) : AnyShapeStyle(.secondary))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ContainerList(containers: [
        ContainerSummary(
            id: 1,
            name: "dashboard",
            status: "running:healthy",
            image: "ghcr.io/get-convex/convex-dashboard:latest",
            link: URL(string: "https://convex.example.com")
        ),
        ContainerSummary(
            id: 2, name: "backend", status: "running:unhealthy", image: "ghcr.io/get-convex/convex-backend"),
        ContainerSummary(id: 3, name: "token-generator", status: "exited"),
    ])
    .frame(width: 480, height: 320)
}

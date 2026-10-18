import CoolifyAPI
import SwiftUI

/// The running containers of a resource, to pick the one the shell opens in.
struct ContainerPicker: View {
    var containers: [DockerContainer]
    var target: TerminalTarget
    var onPick: (DockerContainer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Open a shell in")
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(containers.enumerated()), id: \.element.id) { index, container in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 46)
                    }
                    Button {
                        onPick(container)
                    } label: {
                        HStack(spacing: 14) {
                            FlameGlyph(heat: Heat(status: "running"), height: 20)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(TerminalModel.title(of: container, target: target))
                                    .font(.body.weight(.semibold))
                                    .lineLimit(1)
                                if let image = container.image, !image.isEmpty {
                                    Text(image)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            Spacer(minLength: 8)
                            if let status = container.status {
                                Text(status)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .well()
        }
        .frame(maxWidth: 560)
    }
}

#Preview {
    ContainerPicker(
        containers: [
            DockerContainer(
                id: "a", name: "backend-svc1", image: "ghcr.io/get-convex/convex-backend", state: "running",
                status: "Up 3 hours (healthy)"),
            DockerContainer(
                id: "b", name: "dashboard-svc1", image: "ghcr.io/get-convex/convex-dashboard", state: "running",
                status: "Up 3 hours"),
        ],
        target: TerminalTarget(route: .service("svc1"), resourceName: "convex"),
        onPick: { _ in }
    )
    .padding()
}

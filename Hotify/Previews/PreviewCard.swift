import SwiftUI

/// One preview on the board. It casts light by its state: blue while live, amber when it failed, none when idle,
/// and a blue rim circles it while it builds.
struct PreviewCard: View {
    var preview: PreviewLine
    var onOpen: () -> Void

    @State private var isHovered = false

    private static let radius: CGFloat = 16

    private var cast: Color? {
        switch preview.heat {
        case .lit: .pilot
        case .troubled: .glow
        default: nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                FlameGlyph(heat: preview.heat, height: 22, tone: .preview)
                PullRequestBadge(number: preview.number)
                if preview.isDraft {
                    Tag(text: "Draft")
                }
                Spacer(minLength: 8)
                Text(preview.stateLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FlameTone.preview.tint(for: preview.heat))
                    .contentTransition(.interpolate)
            }

            Text(preview.headline)
                .font(.headline)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)

            if let branch = preview.branch {
                Label(branch, systemImage: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                if let startedAt = preview.latest.startedAt {
                    Text(startedAt, format: .relative(presentation: .named))
                        .help(startedAt.formatted(date: .abbreviated, time: .standard))
                }
                Spacer(minLength: 8)
                if let url = preview.url, preview.state == .live {
                    Link(destination: url) {
                        Label(url.host() ?? url.absoluteString, systemImage: "arrow.up.right")
                            .labelStyle(.titleAndIcon)
                    }
                    .foregroundStyle(.pilot)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
        .background {
            ZStack {
                Color.primary.opacity(isHovered ? 0.07 : 0.045)
                if let cast {
                    // Light thrown up from the flame's corner, as a lamp would.
                    RadialGradient(
                        colors: [cast.opacity(0.2), cast.opacity(0)],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 240
                    )
                    .transition(.opacity)
                }
            }
            .clipShape(.rect(cornerRadius: Self.radius))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Self.radius)
                .strokeBorder((cast ?? .primary).opacity(cast == nil ? 0.06 : 0.22), lineWidth: 1)
        }
        .heatEdge(isActive: preview.state == .building, cornerRadius: Self.radius, tone: .preview)
        .contentShape(.rect(cornerRadius: Self.radius))
        // A tap rather than a button, so the link inside the card still opens.
        .onTapGesture(perform: onOpen)
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.15), value: isHovered)
        .animation(.smooth(duration: 0.5), value: preview.heat)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows this preview")
        .accessibilityAction(.default, onOpen)
    }
}

#Preview {
    let now = Date.now
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
        PreviewCard(
            preview: PreviewLine(
                number: 42,
                deployments: [
                    DeploymentLine(
                        id: "a", status: "finished", pullRequest: 42, startedAt: now.addingTimeInterval(-7_200))
                ],
                title: "Add a pricing page",
                branch: "feat/pricing",
                url: URL(string: "https://42.hotify.example.com")
            )
        ) {}
        PreviewCard(
            preview: PreviewLine(
                number: 41,
                deployments: [
                    DeploymentLine(
                        id: "b", status: "in_progress", pullRequest: 41, startedAt: now.addingTimeInterval(-40))
                ],
                title: "A warmer welcome",
                branch: "feat/welcome",
                isDraft: true
            )
        ) {}
        PreviewCard(
            preview: PreviewLine(
                number: 39,
                deployments: [
                    DeploymentLine(
                        id: "c", status: "failed", message: "chore: bump node to 24", pullRequest: 39,
                        startedAt: now.addingTimeInterval(-86_400))
                ]
            )
        ) {}
    }
    .padding(24)
    .frame(width: 600)
}

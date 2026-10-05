import CoolifyAPI
import SwiftUI

/// An application's deployments, newest first, on a timeline. Previews get their own run below production, in blue,
/// and a filter picks one run when both are there.
struct DeploymentTimeline: View {
    var deployments: [DeploymentLine]
    var isLoading: Bool
    var onSelect: (DeploymentLine) -> Void = { _ in }
    var canLoadMore = false
    var onLoadMore: () -> Void = {}
    /// Opens the previews space. `nil` leaves the link out, as inside a preview.
    var onShowPreviews: (() -> Void)?
    /// The images Coolify kept. A production row that built one of them offers to roll back to it.
    var rollbackImages: [RollbackImage] = []
    /// `nil` leaves Roll Back to This out of the rows' menus.
    var onRollBack: ((RollbackImage) -> Void)?

    @State private var filter = TimelineFilter.all

    private var production: [DeploymentLine] { deployments.filter { !$0.isPreview } }
    private var previews: [DeploymentLine] { deployments.filter(\.isPreview) }

    private var hasBoth: Bool { !production.isEmpty && !previews.isEmpty }

    /// Back to everything once one run empties, so the filter never hides the only deployments there are.
    private var shownFilter: TimelineFilter { hasBoth ? filter : .all }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if hasBoth {
                    Picker("Show", selection: $filter) {
                        ForEach(TimelineFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                if !production.isEmpty, shownFilter != .previews {
                    run("Production", production, tone: .production)
                }
                if !previews.isEmpty, shownFilter != .production {
                    run("Previews", previews, tone: .preview)
                }
                if canLoadMore {
                    Button("Show Older Deployments", systemImage: "clock.arrow.circlepath", action: onLoadMore)
                        .glassButton()
                        .disabled(isLoading)
                        // Lines up with the rows' text, past the timeline's flames.
                        .padding(.leading, 32)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            if deployments.isEmpty {
                if isLoading {
                    ProgressView()
                } else {
                    ContentUnavailableView(
                        "No deployments yet",
                        systemImage: "arrow.up.circle",
                        description: Text("Start or redeploy this application and each build shows up here.")
                    )
                }
            }
        }
        .animation(.snappy, value: deployments)
        .animation(.snappy, value: shownFilter)
    }

    private func run(_ title: String, _ rows: [DeploymentLine], tone: FlameTone) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // A heading only tells the runs apart, so a lone run goes without.
            if hasBoth, shownFilter == .all {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(tone == .preview ? AnyShapeStyle(.pilot) : AnyShapeStyle(.secondary))
                    Spacer()
                    if tone == .preview, let onShowPreviews {
                        Button("Open Previews", action: onShowPreviews)
                            .buttonStyle(.borderless)
                            .font(.subheadline)
                            .foregroundStyle(.pilot)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    DeploymentRow(line: row, isLast: index == rows.count - 1) {
                        onSelect(row)
                    }
                    .contextMenu {
                        if let onRollBack, let image = rollbackTarget(for: row) {
                            Button("Roll Back to This…", systemImage: "arrow.uturn.backward") {
                                onRollBack(image)
                            }
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    /// The image a row built, unless it is the one running.
    private func rollbackTarget(for line: DeploymentLine) -> RollbackImage? {
        guard let image = RollbackModel.image(for: line, in: rollbackImages), !image.isCurrent else { return nil }
        return image
    }
}

/// Which run of the timeline shows.
private enum TimelineFilter: Hashable, CaseIterable, Identifiable {
    case all
    case production
    case previews

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .production: "Production"
        case .previews: "Previews"
        }
    }
}

/// One deployment: its flame on the timeline, what shipped, when, and how long it took. Opens its build output.
private struct DeploymentRow: View {
    var line: DeploymentLine
    var isLast: Bool
    var onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(spacing: 6) {
                FlameGlyph(heat: line.heat, height: 18, tone: line.tone)
                    .padding(.top, 9)
                if !isLast {
                    Capsule()
                        .fill(line.isPreview ? AnyShapeStyle(.pilot.opacity(0.25)) : AnyShapeStyle(.quaternary))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(line.statusLabel)
                        .font(.headline)
                        .foregroundStyle(line.heat.needsAttention ? AnyShapeStyle(.glow) : AnyShapeStyle(.primary))
                    if let pullRequest = line.pullRequest {
                        PullRequestBadge(number: pullRequest)
                    }
                    if line.isRestart {
                        Chip(text: "Restart")
                    }
                    if line.isRollback {
                        Chip(text: "Rollback")
                    }
                    Spacer(minLength: 8)
                    if let startedAt = line.startedAt {
                        Text(startedAt, format: .relative(presentation: .named))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .help(startedAt.formatted(date: .abbreviated, time: .standard))
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }

                if let message = line.message {
                    Text(message)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                }

                if line.commit != nil || line.duration != nil || line.url != nil {
                    HStack(spacing: 14) {
                        if let commit = line.commit {
                            Text(commit)
                                .font(.caption.monospaced())
                        }
                        if let duration = line.duration {
                            Label(
                                duration.formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow)),
                                systemImage: "timer"
                            )
                        }
                        if let url = line.url, let urlLabel = line.urlLabel {
                            Link(destination: url) {
                                Label(urlLabel, systemImage: "arrow.up.right")
                            }
                            .foregroundStyle(.tint)
                            .lineLimit(1)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(isHovered ? 0.045 : 0), in: .rect(cornerRadius: 10))
            .padding(.bottom, isLast ? 0 : 6)
        }
        .contentShape(.rect)
        // A tap rather than a button, so the link inside the row still opens.
        .onTapGesture(perform: onOpen)
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.15), value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows the build output")
        .accessibilityAction(.default, onOpen)
    }
}

#Preview {
    let now = Date.now
    DeploymentTimeline(
        deployments: [
            DeploymentLine(
                id: "3",
                status: "in_progress",
                commit: "9f2c1ab",
                message: "feat: add a pricing page",
                startedAt: now.addingTimeInterval(-40)
            ),
            DeploymentLine(
                id: "2",
                status: "finished",
                commit: "abc1234",
                message: "fix: login redirect",
                startedAt: now.addingTimeInterval(-3_600),
                finishedAt: now.addingTimeInterval(-3_528)
            ),
            DeploymentLine(
                id: "1",
                status: "failed",
                commit: "77aa01e",
                message: "chore: bump node to 24",
                startedAt: now.addingTimeInterval(-86_400),
                finishedAt: now.addingTimeInterval(-86_380)
            ),
            DeploymentLine(
                id: "0",
                status: "finished",
                commit: "5aa01e7",
                message: "fix: retry on 502",
                isRollback: true,
                startedAt: now.addingTimeInterval(-172_800),
                finishedAt: now.addingTimeInterval(-172_790)
            ),
            DeploymentLine(
                id: "p1",
                status: "finished",
                commit: "def5678",
                pullRequest: 18,
                startedAt: now.addingTimeInterval(-7_200),
                finishedAt: now.addingTimeInterval(-7_100),
                url: URL(string: "https://pr-18.example.com")
            ),
        ],
        isLoading: false
    )
    .frame(width: 520, height: 560)
}

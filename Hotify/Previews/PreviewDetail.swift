import CoolifyAPI
import SwiftUI

/// One pull request's preview: where it stands, its builds, and its running output.
struct PreviewDetail: View {
    var preview: PreviewLine
    var model: PreviewsModel
    var client: CoolifyClient?
    var application: String
    /// The build whose output is open. The deploy sheet sets it to follow the build it queued.
    @Binding var selectedDeployment: DeploymentLine?
    var onBack: () -> Void
    var onRemove: (PreviewLine) -> Void

    @State private var tab = PreviewTab.activity
    @State private var logs = PreviewLogModel()
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let selectedDeployment {
                DeploymentDetail(client: client, initial: selectedDeployment, backTitle: "PR #\(preview.number)") {
                    self.selectedDeployment = nil
                }
                .padding(.top, 16)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                overview
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: selectedDeployment)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Button("Previews", systemImage: "chevron.left", action: onBack)
                    .buttonStyle(.borderless)
                    .fontWeight(.medium)
                    .help("Back to all previews")
                    .keyboardShortcut(.cancelAction)
                PreviewHeader(preview: preview)
                actionBar
                if let error = model.actionError {
                    NoticeBanner(message: error)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 18)

            Picker("Show", selection: $tab) {
                ForEach(PreviewTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            Group {
                switch tab {
                case .activity:
                    DeploymentTimeline(
                        deployments: preview.deployments,
                        isLoading: false,
                        onSelect: { selectedDeployment = $0 }
                    )
                case .logs:
                    VStack(spacing: 10) {
                        if let error = logs.error, preview.state == .live {
                            NoticeBanner(message: error)
                                .padding(.horizontal, 20)
                        }
                        LogView(
                            lines: logs.lines,
                            rawLogs: logs.logs,
                            isLoading: logs.isLoading,
                            lineCount: $logs.lineCount,
                            pausedMessage: pausedMessage
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
        .animation(.snappy, value: tab)
        .animation(.snappy, value: model.actionError)
        .task(id: LogKey(number: preview.number, isLive: preview.state == .live, tab: tab, lines: logs.lineCount)) {
            guard tab == .logs, preview.state == .live, let client else { return }
            await logs.follow(client: client, application: application, number: preview.number)
        }
    }

    /// Coolify only serves output for a running preview.
    private var pausedMessage: String? {
        switch preview.state {
        case .live: nil
        case .building: "PR #\(preview.number) is building. Its output shows here once it runs."
        case .failed: "The last build failed, so nothing is running. Open it under Activity to see why."
        case .cancelled: "The last build was cancelled. Redeploy to run this preview again."
        case .removed: "This preview was removed. Deploy it again to bring it back."
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if let building = preview.activeDeployment {
                Button("Cancel Build", systemImage: "xmark") {
                    Task { await model.cancel(building) }
                }
                .glassButton()
                .help("Stop this build. The preview keeps what it ran before.")
            } else {
                Button(
                    preview.state == .removed ? "Deploy Again" : "Redeploy",
                    systemImage: "arrow.triangle.2.circlepath"
                ) {
                    Task {
                        if let queued = await model.redeploy(preview.number) {
                            selectedDeployment = queued
                        }
                    }
                }
                .glassButton(prominent: true)
                .disabled(preview.work != nil || client == nil)
                .help("Build the pull request's latest commit again")
            }
            if let url = preview.url, preview.state == .live {
                Link(destination: url) {
                    Label("Open Preview", systemImage: "safari")
                }
                .glassButton()
            }
            Menu {
                if let url = model.gitHubURL(for: preview.number) {
                    Link(destination: url) {
                        Label("Open Pull Request on GitHub", systemImage: "arrow.triangle.pull")
                    }
                    Divider()
                }
                Button("Remove Preview…", systemImage: "trash", role: .destructive) {
                    onRemove(preview)
                }
                .disabled(preview.work != nil || preview.state == .removed)
            } label: {
                Label("More Actions", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
            }
            .menuIndicator(.hidden)
            .glassButton()
        }
        .controlSize(.large)
    }
}

/// What restarts the log poll: another preview, the preview coming up or going down, or a new line count.
private struct LogKey: Hashable {
    var number: Int
    var isLive: Bool
    var tab: PreviewTab
    var lines: Int
}

/// The head of a preview: its flame, the PR's title, and where it is.
private struct PreviewHeader: View {
    var preview: PreviewLine

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            FlameGlyph(heat: preview.heat, height: 56, ignitesOnAppear: true, tone: .preview, breathes: true)

            VStack(alignment: .leading, spacing: 6) {
                Text(preview.headline)
                    .font(.display(.title2))
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .textSelection(.enabled)

                HStack(spacing: 10) {
                    PullRequestBadge(number: preview.number)
                    if preview.isDraft {
                        Tag(text: "Draft")
                    }
                    Text(preview.stateLabel)
                        .fontWeight(.semibold)
                        .foregroundStyle(FlameTone.preview.tint(for: preview.heat))
                        .contentTransition(.interpolate)
                    if let branch = preview.branch {
                        Label(branch, systemImage: "arrow.triangle.branch")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .font(.subheadline)

                if let url = preview.url, preview.state == .live {
                    Link(destination: url) {
                        Label(url.host() ?? url.absoluteString, systemImage: "arrow.up.right")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.pilot)
                    .lineLimit(1)
                }
            }
        }
        .animation(.snappy, value: preview.heat)
    }
}

/// The views under a preview's header.
enum PreviewTab: Hashable, CaseIterable, Identifiable {
    case activity
    case logs

    var id: Self { self }

    var title: String {
        switch self {
        case .activity: "Activity"
        case .logs: "Logs"
        }
    }
}

#Preview {
    @Previewable @State var selected: DeploymentLine?
    let now = Date.now
    PreviewDetail(
        preview: PreviewLine(
            number: 42,
            deployments: [
                DeploymentLine(
                    id: "b", status: "finished", commit: "9f2c1ab", message: "feat: add a pricing page",
                    pullRequest: 42,
                    startedAt: now.addingTimeInterval(-3_600), finishedAt: now.addingTimeInterval(-3_540)),
                DeploymentLine(
                    id: "a", status: "failed", commit: "77aa01e", message: "wip: pricing", pullRequest: 42,
                    startedAt: now.addingTimeInterval(-7_200), finishedAt: now.addingTimeInterval(-7_170)),
            ],
            title: "Add a pricing page",
            branch: "feat/pricing",
            url: URL(string: "https://42.hotify.example.com")
        ),
        model: PreviewsModel(repository: try? GitHubRepository("hotify/website")),
        client: nil,
        application: "app",
        selectedDeployment: $selected,
        onBack: {},
        onRemove: { _ in }
    )
    .tint(.pilot)
    .frame(width: 640, height: 720)
}

import CoolifyAPI
import SwiftUI

/// Every preview of one application as cards, narrowed by state chips and a search.
struct PreviewBoard: View {
    var resourceName: String
    var previews: [PreviewLine]
    var model: PreviewsModel
    var isLoading: Bool
    var canLoadMore = false
    var onLoadMore: () -> Void = {}
    var onBack: () -> Void
    var onDeploy: () -> Void
    var onOpen: (Int) -> Void
    var onRemove: (PreviewLine) -> Void

    @State private var filter = PreviewFilter.all
    @State private var query = ""

    private var shown: [PreviewLine] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return previews.filter { preview in
            filter.includes(preview)
                && (trimmed.isEmpty
                    || "#\(preview.number) \(preview.headline) \(preview.branch ?? "")".localizedStandardContains(
                        trimmed))
        }
    }

    /// Building first, because it changes soonest. Then live, so an empty board still reads as up when one is.
    private var heroHeat: Heat {
        let states = Set(previews.map(\.state))
        if states.contains(.building) { return .warming }
        if states.contains(.live) { return .lit }
        if states.contains(.failed) { return .troubled }
        return .cold
    }

    private var summary: String {
        let parts: [(PreviewState, String)] = [(.live, "live"), (.building, "building"), (.failed, "failed")]
        let counts = parts.compactMap { state, word -> String? in
            let count = previews.count { $0.state == state }
            return count > 0 ? "\(count) \(word)" : nil
        }
        if previews.isEmpty { return "No previews yet" }
        return counts.isEmpty ? "None running" : counts.joined(separator: ", ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button(resourceName, systemImage: "chevron.left", action: onBack)
                    .buttonStyle(.borderless)
                    .fontWeight(.medium)
                    .help("Back to \(resourceName)")
                    .keyboardShortcut(.cancelAction)

                hero

                if let error = model.actionError {
                    NoticeBanner(message: error)
                }

                if !previews.isEmpty {
                    controls
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                    ForEach(shown) { preview in
                        PreviewCard(preview: preview) { onOpen(preview.number) }
                            .contextMenu { menu(for: preview) }
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                    }
                }

                emptyState

                if canLoadMore {
                    Button("Look Further Back", systemImage: "clock.arrow.circlepath", action: onLoadMore)
                        .glassButton()
                        .disabled(isLoading)
                        .help("Load older deployments to find earlier previews")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.snappy, value: shown.map(\.id))
        .animation(.snappy, value: model.actionError)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 18) {
                FlameGlyph(heat: heroHeat, height: 56, ignitesOnAppear: true, tone: .preview, breathes: true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Previews")
                        .font(.display(.title))
                    HStack(spacing: 12) {
                        Text(summary)
                            .fontWeight(.semibold)
                            .foregroundStyle(FlameTone.preview.tint(for: heroHeat))
                            .contentTransition(.interpolate)
                        if let repository = model.repository {
                            Label(repository.label, systemImage: "arrow.triangle.branch")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .font(.subheadline)
                }
            }
            Button("Deploy a Preview…", systemImage: "arrow.triangle.pull", action: onDeploy)
                .glassButton(prominent: true)
                .controlSize(.large)
        }
    }

    /// The chips and the search on one line when they fit, stacked on a phone.
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                PreviewFilterBar(previews: previews, selection: $filter)
                Spacer(minLength: 12)
                search.frame(width: 200)
            }
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    PreviewFilterBar(previews: previews, selection: $filter)
                }
                search
            }
        }
    }

    private var search: some View {
        TextField("Search PRs or branches", text: $query)
            .textFieldStyle(.roundedBorder)
    }

    @ViewBuilder
    private func menu(for preview: PreviewLine) -> some View {
        if let url = preview.url {
            Link(destination: url) {
                Label("Open Preview", systemImage: "safari")
            }
        }
        if let url = model.gitHubURL(for: preview.number) {
            Link(destination: url) {
                Label("Open Pull Request on GitHub", systemImage: "arrow.triangle.pull")
            }
        }
        Divider()
        Button("Redeploy", systemImage: "arrow.triangle.2.circlepath") {
            Task { await model.redeploy(preview.number) }
        }
        .disabled(preview.work != nil)
        Button("Remove Preview…", systemImage: "trash", role: .destructive) {
            onRemove(preview)
        }
        .disabled(preview.work != nil || preview.state == .removed)
    }

    @ViewBuilder
    private var emptyState: some View {
        if previews.isEmpty {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
            } else {
                ContentUnavailableView {
                    Label("No previews yet", systemImage: "arrow.triangle.pull")
                } description: {
                    Text(
                        "Deploy a pull request to try it on its own address before it reaches \(resourceName). Older previews may sit further back in the history."
                    )
                }
                .padding(.top, 12)
            }
        } else if shown.isEmpty {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView(
                    "Nothing \(filter.title.lowercased())",
                    systemImage: "line.3.horizontal.decrease",
                    description: Text("No preview is in this state right now.")
                )
            } else {
                ContentUnavailableView.search(text: query)
            }
        }
    }
}

#Preview {
    let now = Date.now
    PreviewBoard(
        resourceName: "marketing-site",
        previews: [
            PreviewLine(
                number: 42,
                deployments: [
                    DeploymentLine(
                        id: "a", status: "in_progress", pullRequest: 42, startedAt: now.addingTimeInterval(-30))
                ],
                title: "Add a pricing page",
                branch: "feat/pricing"
            ),
            PreviewLine(
                number: 41,
                deployments: [
                    DeploymentLine(
                        id: "b", status: "finished", pullRequest: 41, startedAt: now.addingTimeInterval(-3_600))
                ],
                title: "A warmer welcome",
                branch: "feat/welcome",
                url: URL(string: "https://41.hotify.example.com")
            ),
            PreviewLine(
                number: 37,
                deployments: [
                    DeploymentLine(
                        id: "c", status: "failed", message: "chore: bump node to 24", pullRequest: 37,
                        startedAt: now.addingTimeInterval(-86_400))
                ]
            ),
        ],
        model: PreviewsModel(repository: try? GitHubRepository("hotify/website")),
        isLoading: false,
        canLoadMore: true,
        onBack: {},
        onDeploy: {},
        onOpen: { _ in },
        onRemove: { _ in }
    )
    .tint(.pilot)
    .frame(width: 640, height: 720)
}

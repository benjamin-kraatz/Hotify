import SwiftUI

/// Every pull request preview in the project, as cards under the application that builds them. It burns blue
/// throughout, like the previews space of one application, which each card opens.
struct ProjectPreviews: View {
    var projectName: String
    var groups: [ApplicationPreviews]
    /// The history is still on its way, so no cards does not yet mean no previews.
    var isLoading = false
    var gitHubURL: (ResourceRoute, Int) -> URL? = { _, _ in nil }
    var onOpen: (ApplicationPreviews, PreviewPlace) -> Void

    @State private var filter = PreviewFilter.all

    private var all: [PreviewLine] { groups.flatMap(\.previews) }

    private var shown: [ApplicationPreviews] {
        groups.compactMap { group in
            var group = group
            group.previews = group.previews.filter(filter.includes)
            return group.previews.isEmpty ? nil : group
        }
    }

    var body: some View {
        let shown = shown
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !groups.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        PreviewFilterBar(previews: all, selection: $filter)
                            // Room for the selected chip's border, which a scroll view would clip.
                            .padding(1)
                    }
                }

                ForEach(shown) { group in
                    section(group)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            emptyState(isFiltered: shown.isEmpty && !groups.isEmpty)
        }
        .tint(.pilot)
        .animation(.snappy, value: shown.map(\.id))
        .animation(.snappy, value: shown.flatMap { $0.previews.map(\.id) })
    }

    private func section(_ group: ApplicationPreviews) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.name)
                    .font(.headline)
                    .foregroundStyle(.pilot)
                    .lineLimit(1)
                if let environment = group.environmentName, !environment.isEmpty {
                    EnvironmentBadge(name: environment)
                }
                if let repository = group.repository {
                    Label(repository, systemImage: "arrow.triangle.branch")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Button("Open Previews") {
                    onOpen(group, .board)
                }
                .buttonStyle(.borderless)
                .font(.subheadline)
                .foregroundStyle(.pilot)
                .help("Show the previews of \(group.name), where you can deploy, redeploy, and remove them")
            }
            .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                ForEach(group.previews) { preview in
                    PreviewCard(preview: preview) {
                        onOpen(group, .preview(preview.number))
                    }
                    .contextMenu { menu(for: preview, in: group) }
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
        }
    }

    @ViewBuilder
    private func menu(for preview: PreviewLine, in group: ApplicationPreviews) -> some View {
        Button("Show in \(group.name)", systemImage: "arrow.triangle.pull") {
            onOpen(group, .preview(preview.number))
        }
        if let url = preview.url, preview.state == .live {
            Link(destination: url) {
                Label("Open Preview", systemImage: "safari")
            }
        }
        if let url = gitHubURL(group.application, preview.number) {
            Link(destination: url) {
                Label("Open Pull Request on GitHub", systemImage: "arrow.up.right")
            }
        }
    }

    @ViewBuilder
    private func emptyState(isFiltered: Bool) -> some View {
        if isFiltered {
            ContentUnavailableView(
                "Nothing \(filter.title.lowercased())",
                systemImage: "line.3.horizontal.decrease",
                description: Text("No preview is in this state right now.")
            )
        } else if groups.isEmpty {
            if isLoading {
                ProgressView()
            } else {
                ContentUnavailableView {
                    Label("No previews in this project", systemImage: "arrow.triangle.pull")
                } description: {
                    Text(
                        "Deploy a pull request from an application's Previews menu and it shows up here, beside the previews of everything else in \(projectName)."
                    )
                }
            }
        }
    }
}

#Preview {
    let now = Date.now
    ProjectPreviews(
        projectName: "Website",
        groups: [
            ApplicationPreviews(
                application: .application("web"),
                name: "marketing-site",
                repository: "hotify/website",
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
                ]
            ),
            ApplicationPreviews(
                application: .application("api"),
                name: "api",
                repository: "hotify/api",
                previews: [
                    PreviewLine(
                        number: 42,
                        deployments: [
                            DeploymentLine(
                                id: "c", status: "failed", message: "chore: bump node to 24", pullRequest: 42,
                                startedAt: now.addingTimeInterval(-86_400))
                        ]
                    )
                ]
            ),
        ],
        onOpen: { _, _ in }
    )
    .frame(width: 640, height: 640)
}

#Preview("Empty") {
    ProjectPreviews(projectName: "Website", groups: [], onOpen: { _, _ in })
        .frame(width: 640, height: 420)
}

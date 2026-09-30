import CoolifyAPI
import SwiftUI

/// Chooses a PR and deploys its preview, with optional GitHub access for private repositories.
struct PreviewDeploymentSheet: View {
    var client: CoolifyClient?
    var application: String
    var previousPRs: [Int] = []
    var resourceName: String
    var onQueued: (QueuedDeployment, Int) -> Void

    @SwiftUI.Environment(\.dismiss) private var dismiss
    @State private var model = PreviewDeploymentModel()
    @State private var selected: Int?
    @State private var search = ""
    @State private var manualNumber = ""
    @State private var loadID = 0
    @State private var loadMore = false
    @State private var showsGitHubAccess = false

    init(
        client: CoolifyClient?, application: String, previousPRs: [Int] = [], resourceName: String,
        model: PreviewDeploymentModel? = nil,
        onQueued: @escaping (QueuedDeployment, Int) -> Void
    ) {
        self.client = client
        self.application = application
        self.previousPRs = previousPRs
        self.resourceName = resourceName
        self.onQueued = onQueued
        _model = State(initialValue: model ?? PreviewDeploymentModel())
    }

    private var number: Int? {
        manualNumber.isEmpty ? selected : Int(manualNumber).flatMap { $0 > 0 ? $0 : nil }
    }

    private var filtered: [PreviewChoice] {
        model.choices.filter {
            search.isEmpty
                || "\($0.number) \($0.title ?? "") \($0.branch ?? "")".localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Deploy a preview", systemImage: "arrow.triangle.pull")
                            .font(.display(.title2))
                        Text(
                            "Pick a pull request for \(resourceName). Its preview uses the application's preview variables."
                        )
                        .foregroundStyle(.secondary)
                        if let repository = model.repository {
                            Text(repository.label).font(.subheadline.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Set up new previews in Coolify first")
                            .font(.headline)
                        Text(
                            "Add a PR in the application's Previews page, or let its Git integration create it. Then deploy it here."
                        )
                        .font(.subheadline).foregroundStyle(.secondary)
                        if let url = model.setupURL {
                            Link("Open Coolify", destination: url)
                        }
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).well()

                    if let error = model.loadError { NoticeBanner(message: error) }
                    if let error = model.deployError { NoticeBanner(message: error) }

                    DisclosureGroup("Deploy by PR number") {
                        TextField("PR number", text: $manualNumber)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                        .keyboardType(.numberPad)
                            #endif
                            .padding(.top, 8)
                    }
                    .font(.subheadline)
                    Button("GitHub Access…", systemImage: "key") { showsGitHubAccess = true }
                        .font(.subheadline)
                        .disabled(model.isDeploying)

                    HStack {
                        Text("Pull requests").font(.headline)
                        Spacer()
                        Button("Reload", systemImage: "arrow.clockwise") {
                            loadMore = false
                            loadID += 1
                        }
                        .labelStyle(.iconOnly)
                        .disabled(model.isLoading || model.isDeploying)
                    }
                    TextField("Search PRs or branches", text: $search)
                        .textFieldStyle(.roundedBorder)
                    if model.isLoading { ProgressView().frame(maxWidth: .infinity) }
                    if filtered.isEmpty, !model.isLoading {
                        Text(
                            model.choices.isEmpty
                                ? "No pull requests loaded. Connect GitHub for a private repository, or use Deploy by PR number."
                                : "No matching pull requests."
                        )
                        .font(.subheadline).foregroundStyle(.secondary)
                    }
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { choice in
                            choiceButton(choice)
                        }
                    }
                    if model.nextPage != nil {
                        Button("Load More Pull Requests") {
                            loadMore = true
                            loadID += 1
                        }
                        .disabled(model.isLoading || model.isDeploying)
                    }

                }
                .padding(24)
            }
            .disabled(model.isDeploying)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(number.map { "Preview · PR #\(String($0))" } ?? "Choose a pull request")
                            .font(.subheadline.weight(.semibold))
                        Text(model.isDeploying ? "Waiting for Coolify…" : "Uses the preview environment")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button("Deploy", systemImage: "flame") { deploy() }
                        .glassButton(prominent: true)
                        .disabled(number == nil || client == nil || model.isLoading || model.isDeploying)
                }
                .padding(20)
                .background(.bar)
            }
            .navigationTitle("Preview deployment")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(model.isDeploying)
                }
            }
        }
        .onChange(of: number) { _, _ in model.deployError = nil }
        .interactiveDismissDisabled(model.isDeploying)
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 540, minHeight: 620)
        #endif
        .task(id: loadID) {
            guard let client else { return }
            await model.load(
                client: client, application: application, token: GitHubCredentialStore.load(), previousPRs: previousPRs,
                more: loadMore)
        }
        .sheet(isPresented: $showsGitHubAccess) {
            GitHubAccessSheet {
                loadMore = false
                loadID += 1
            }
        }
    }

    private func choiceButton(_ choice: PreviewChoice) -> some View {
        Button {
            selected = choice.number
            manualNumber = ""
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.triangle.pull").foregroundStyle(.tint).padding(.top, 3)
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: choice.title ?? "Pull request #\(choice.number)")
                        .font(.body.weight(.medium)).foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(
                        [
                            "#\(choice.number)", choice.branch, choice.isDraft ? "Draft" : nil,
                            choice.wasDeployed ? "Previously deployed" : nil,
                        ].compactMap { $0 }.joined(separator: " · ")
                    )
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(
                    systemName: selected == choice.number && manualNumber.isEmpty ? "checkmark.circle.fill" : "circle"
                )
                .foregroundStyle(
                    selected == choice.number && manualNumber.isEmpty ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).well()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected == choice.number && manualNumber.isEmpty ? .isSelected : [])
    }

    private func deploy() {
        guard let client, let number, !model.isDeploying else { return }
        Task {
            if let queued = await model.deploy(client: client, application: application, number: number) {
                onQueued(queued, number)
                dismiss()
            }
        }
    }
}

#Preview {
    let model = PreviewDeploymentModel()
    model.repository = try? GitHubRepository("hotify/website")
    model.choices = [
        PreviewChoice(number: 42, title: "Add a pricing page", branch: "feat/pricing", wasDeployed: true),
        PreviewChoice(number: 41, title: "A warmer welcome", branch: "feat/welcome", isDraft: true),
    ]
    return PreviewDeploymentSheet(client: nil, application: "example", resourceName: "marketing-site", model: model) {
        _, _ in
    }
}

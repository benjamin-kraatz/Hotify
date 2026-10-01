import CoolifyAPI
import SwiftUI

/// Chooses a PR and deploys its preview, with optional GitHub access for private repositories.
///
/// Each PR carries its preview's flame: lit blue when live, a dashed outline when it has none yet. The flame at the
/// top stays cold until a PR is picked, then lights.
struct PreviewDeploymentSheet: View {
    var client: CoolifyClient?
    var application: String
    var previews: [PreviewLine] = []
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
        client: CoolifyClient?, application: String, previews: [PreviewLine] = [], resourceName: String,
        model: PreviewDeploymentModel? = nil,
        onQueued: @escaping (QueuedDeployment, Int) -> Void
    ) {
        self.client = client
        self.application = application
        self.previews = previews
        self.resourceName = resourceName
        self.onQueued = onQueued
        _model = State(initialValue: model ?? PreviewDeploymentModel())
    }

    private var number: Int? {
        manualNumber.isEmpty ? selected : Int(manualNumber).flatMap { $0 > 0 ? $0 : nil }
    }

    private var chosen: PreviewChoice? {
        number.flatMap { number in model.choices.first { $0.number == number } }
    }

    private var filtered: [PreviewChoice] {
        let trimmed = search.trimmingCharacters(in: .whitespaces)
        return model.choices.filter {
            trimmed.isEmpty
                || "#\($0.number) \($0.headline) \($0.branch ?? "")".localizedStandardContains(trimmed)
        }
    }

    private var withPreview: [PreviewChoice] { filtered.filter { $0.state != nil } }
    private var withoutPreview: [PreviewChoice] { filtered.filter { $0.state == nil } }

    /// What deploying the chosen PR will do, by where its preview stands.
    private var consequence: String {
        if model.isDeploying { return "Waiting for Coolify…" }
        guard number != nil else { return "Its preview builds with the preview variables." }
        switch chosen?.state {
        case .live: return "Builds it again and replaces the live preview."
        case .building: return "Queues another build after the one running."
        case .failed: return "Tries the build again."
        case .cancelled, .removed: return "Builds the preview again."
        case nil: return "Builds this pull request's preview."
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    if let error = model.loadError { NoticeBanner(message: error) }
                    if let error = model.deployError { NoticeBanner(message: error) }

                    HStack(spacing: 10) {
                        TextField("Search PRs or branches", text: $search)
                            .textFieldStyle(.roundedBorder)
                        Button("Reload", systemImage: "arrow.clockwise") {
                            loadMore = false
                            loadID += 1
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(model.isLoading || model.isDeploying)
                    }

                    if !withPreview.isEmpty {
                        section("Previews", withPreview)
                    }
                    if !withoutPreview.isEmpty {
                        section("Open pull requests", withoutPreview)
                    }
                    if model.isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if filtered.isEmpty {
                        Text(
                            model.choices.isEmpty
                                ? "No pull requests loaded. Connect GitHub for a private repository, or deploy by PR number below."
                                : "No matching pull requests."
                        )
                        .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if model.nextPage != nil {
                        Button("Load More Pull Requests") {
                            loadMore = true
                            loadID += 1
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.isLoading || model.isDeploying)
                    }

                    DisclosureGroup("Deploy by PR number") {
                        TextField("PR number", text: $manualNumber)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                        .keyboardType(.numberPad)
                            #endif
                            .padding(.top, 8)
                    }
                    .font(.subheadline)

                    footnote
                }
                .padding(24)
            }
            .disabled(model.isDeploying)
            .safeAreaInset(edge: .bottom, spacing: 0) { deployBar }
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
        .tint(.pilot)
        .onChange(of: number) { _, _ in model.deployError = nil }
        .interactiveDismissDisabled(model.isDeploying)
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 640)
        #endif
        .task(id: loadID) {
            guard let client else { return }
            await model.load(
                client: client, application: application, token: GitHubCredentialStore.load(), previews: previews,
                more: loadMore)
        }
        .sheet(isPresented: $showsGitHubAccess) {
            GitHubAccessSheet(repository: model.repository) {
                loadMore = false
                loadID += 1
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            FlameGlyph(heat: number == nil ? .cold : .lit, height: 44, tone: .preview, breathes: true)
            VStack(alignment: .leading, spacing: 5) {
                Text("Deploy a preview")
                    .font(.display(.title2))
                Text("Pick a pull request of \(resourceName). It runs on its own address, apart from production.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let repository = model.repository {
                    Label(repository.label, systemImage: "arrow.triangle.branch")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func section(_ title: String, _ choices: [PreviewChoice]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            LazyVStack(spacing: 8) {
                ForEach(choices) { choice in
                    choiceButton(choice)
                }
            }
        }
    }

    private func choiceButton(_ choice: PreviewChoice) -> some View {
        let isSelected = selected == choice.number && manualNumber.isEmpty
        return Button {
            selected = choice.number
            manualNumber = ""
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // A dashed outline stands for a PR with no preview yet.
                FlameGlyph(heat: choice.state?.heat ?? .unknown, height: 18, tone: .preview)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: choice.headline)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        PullRequestBadge(number: choice.number)
                        if let state = choice.state {
                            Text(state.label)
                                .fontWeight(.semibold)
                                .foregroundStyle(FlameTone.preview.tint(for: state.heat))
                        }
                        if choice.isDraft {
                            Tag(text: "Draft")
                        }
                        if let branch = choice.branch {
                            Label(branch, systemImage: "arrow.triangle.branch")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .font(.caption)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AnyShapeStyle(.pilot) : AnyShapeStyle(.tertiary))
                    .imageScale(.large)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? AnyShapeStyle(.pilot.opacity(0.12)) : AnyShapeStyle(.primary.opacity(0.045)),
                in: .rect(cornerRadius: 14)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.pilot.opacity(isSelected ? 0.5 : 0), lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                "A pull request needs a preview in Coolify before it deploys here. Add one on the application's Previews page, or let its Git integration create it."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                if let url = model.setupURL {
                    Link("Open Coolify", destination: url)
                }
                Button("GitHub Access…") { showsGitHubAccess = true }
                    .buttonStyle(.borderless)
            }
            .font(.footnote.weight(.medium))
        }
    }

    private var deployBar: some View {
        HStack(spacing: 14) {
            if let number {
                FlameGlyph(
                    heat: model.isDeploying ? .warming : chosen?.state?.heat ?? .unknown, height: 22, tone: .preview
                )
                .transition(.scale.combined(with: .opacity))
                VStack(alignment: .leading, spacing: 3) {
                    Text(chosen?.headline ?? "Pull request #\(number)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(consequence)
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose a pull request")
                        .font(.subheadline.weight(.semibold))
                    Text(consequence)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button("Deploy Preview", systemImage: "arrow.triangle.pull") { deploy() }
                .glassButton(prominent: true)
                .controlSize(.large)
                .disabled(number == nil || client == nil || model.isLoading || model.isDeploying)
        }
        .padding(20)
        .background(.bar)
        .animation(.snappy, value: number)
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
        PreviewChoice(number: 42, title: "Add a pricing page", branch: "feat/pricing", state: .live),
        PreviewChoice(number: 41, title: "A warmer welcome", branch: "feat/welcome", isDraft: true, state: .failed),
        PreviewChoice(number: 40, title: "Darker log well", branch: "fix/log-contrast"),
    ]
    return PreviewDeploymentSheet(client: nil, application: "example", resourceName: "marketing-site", model: model) {
        _, _ in
    }
}

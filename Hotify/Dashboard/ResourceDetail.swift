import CoolifyAPI
import SwiftUI

/// Deployments, containers, logs, variables, and settings for one application, database, or service. Polls while it
/// is on screen.
struct ResourceDetailScreen: View {
    var client: CoolifyClient?
    var resource: ResourceSummary
    var pendingAction: ResourceAction?
    /// The last action that failed, from the dashboard. The middle column is off screen on iPhone.
    var actionError: String?
    /// Set when the project page led here, so the screen offers the way back to it.
    var back: DetailBack?
    var onOpenProject: (() -> Void)?
    var onAction: (ResourceAction) -> Void

    @State private var model: ResourceDetailModel
    @State private var variables: VariablesModel
    @State private var configuration: ConfigurationModel
    @State private var previews = PreviewsModel()
    @State private var chosenContainerID: Int?
    @State private var tab: DetailTab?
    @State private var previewPlace: PreviewPlace?

    /// `entry` picks where the screen opens, such as on the preview the project page led here from.
    init(
        client: CoolifyClient?,
        resource: ResourceSummary,
        pendingAction: ResourceAction?,
        actionError: String? = nil,
        entry: ResourceEntry? = nil,
        model: ResourceDetailModel = ResourceDetailModel(),
        variables: VariablesModel = VariablesModel(),
        configuration: ConfigurationModel = ConfigurationModel(),
        back: DetailBack? = nil,
        onOpenProject: (() -> Void)? = nil,
        onAction: @escaping (ResourceAction) -> Void
    ) {
        self.client = client
        self.resource = resource
        self.pendingAction = pendingAction
        self.actionError = actionError
        self.back = back
        self.onOpenProject = onOpenProject
        self.onAction = onAction
        if let entry, !entry.history.isEmpty {
            model.seed(entry.history, for: resource.route)
        }
        _model = State(initialValue: model)
        _variables = State(initialValue: variables)
        _configuration = State(initialValue: configuration)
        switch entry?.place {
        case .deployments:
            _tab = State(initialValue: .deployments)
        case .previews(let place):
            _previewPlace = State(initialValue: place)
        case nil:
            break
        }
    }

    /// The container whose logs show: the one picked, else the first running one, else the first.
    private var logContainer: ContainerSummary? {
        let containers = resource.containers
        return containers.first { $0.id == chosenContainerID }
            ?? containers.first { $0.heat != .cold && $0.heat != .unknown }
            ?? containers.first
    }

    private var logSource: LogSource? {
        switch resource.kind {
        case .application, .database:
            return resource.heat == .cold ? nil : .resource
        case .service:
            guard let logContainer, logContainer.heat != .cold, !logContainer.serviceName.isEmpty else { return nil }
            return .container(logContainer.serviceName)
        }
    }

    var body: some View {
        @Bindable var model = model

        ResourceDetail(
            resource: resource,
            pendingAction: pendingAction,
            logContainer: logContainer,
            chosenContainerID: $chosenContainerID,
            tab: $tab,
            previewPlace: $previewPlace,
            logLines: model.logLines,
            rawLogs: model.logs,
            logLineCount: $model.logLineCount,
            deployments: model.deployments,
            variables: variables,
            configuration: configuration,
            previewsModel: previews,
            loadError: model.loadError,
            actionError: actionError,
            isLoading: model.isLoading,
            deploymentClient: client,
            canLoadMoreDeployments: model.canLoadMoreDeployments,
            onLoadMoreDeployments: {
                model.deploymentLimit += 20
                Task { await model.refresh() }
            },
            back: back,
            onOpenProject: onOpenProject,
            onAction: onAction
        )
        .task(id: resource.route) {
            guard let client else { return }
            model.prepare(client, route: resource.route)
            variables.prepare(client, route: resource.route)
            configuration.prepare(client, route: resource.route)
            previews.prepare(client, route: resource.route)
            Task { await previews.load() }
            await model.setLogSource(logSource)
            while !Task.isCancelled {
                await model.refresh()
                if Task.isCancelled { return }
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .onChange(of: model.logLineCount) { _, _ in
            Task { await model.refresh() }
        }
        .onChange(of: logSource) { _, source in
            Task { await model.setLogSource(source) }
        }
        // Pick up the finished deployment now rather than on the next poll.
        .onChange(of: resource.isDeploying) { _, _ in
            Task { await model.refresh() }
        }
        .onChange(of: resource.buildingPreviews) { _, _ in
            Task { await model.refresh() }
        }
    }
}

/// The detail layout. Takes plain values, and models without a client, so a preview does not need one.
struct ResourceDetail: View {
    var resource: ResourceSummary
    var pendingAction: ResourceAction?
    var logContainer: ContainerSummary?
    @Binding var chosenContainerID: Int?
    /// The tab the user picked. `nil` lets the resource's state choose.
    @Binding var tab: DetailTab?
    /// Open while the previews take over the column. `nil` shows production.
    @Binding var previewPlace: PreviewPlace?
    var logLines: [LogLine]
    var rawLogs: String
    @Binding var logLineCount: Int
    var deployments: [DeploymentLine]
    var variables: VariablesModel
    var configuration = ConfigurationModel()
    var previewsModel = PreviewsModel()
    var loadError: String?
    var actionError: String?
    var isLoading: Bool
    var deploymentClient: CoolifyClient?
    var canLoadMoreDeployments = false
    var onLoadMoreDeployments: () -> Void = {}
    /// Where back leads from the resource's own screen. `nil` when the resource is the top of the column.
    var back: DetailBack?
    var onOpenProject: (() -> Void)?
    var onAction: (ResourceAction) -> Void

    #if os(macOS)
    /// Missing in previews, which leaves the menu bar button out.
    @SwiftUI.Environment(MenuBarModel.self) private var menuBar: MenuBarModel?
    #endif
    @State private var selectedDeployment: DeploymentLine?
    @State private var stopCandidate: ResourceSummary?
    @State private var showsPreviewDeployment = false
    @State private var showsGitHubAccess = false
    @State private var previewGeneration = 0
    @State private var followedPreviewDeployment: DeploymentLine?
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tabs: [DetailTab] {
        switch resource.kind {
        case .application: [.logs, .deployments, .variables, .settings]
        case .service: [.logs, .containers, .variables, .settings]
        case .database: [.logs, .backups, .variables, .settings]
        }
    }

    private var previews: [PreviewLine] {
        resource.kind == .application ? previewsModel.previews(from: deployments) : []
    }

    private var lastDeploymentFailed: Bool {
        deployments.first { !$0.isPreview }?.status == "failed"
    }

    /// Coolify only serves logs for running containers, so a stopped one gets a note instead of an error.
    private var pausedMessage: String? {
        switch resource.kind {
        case .application, .database:
            guard resource.heat == .cold else { return nil }
            if resource.isDeploying || pendingAction == .start {
                return "\(resource.name) is on its way up. Its output shows here once it runs."
            }
            return "\(resource.name) isn't running, so there is no output. Start it to see its logs."
        case .service:
            guard let logContainer, logContainer.heat == .cold else { return nil }
            return "\(logContainer.name) isn't running. Start the service to read its output."
        }
    }

    /// Until the user picks a tab, an app that is building or stopped opens on its deployments, which say why.
    private var currentTab: DetailTab {
        if let tab, tabs.contains(tab) {
            return tab
        }
        if resource.kind == .application, resource.isDeploying || resource.heat == .cold {
            return .deployments
        }
        return tabs[0]
    }

    /// The deployment whose build output is on screen, which takes the back button until it closes.
    private var openDeployment: DeploymentLine? {
        currentTab == .deployments ? selectedDeployment : nil
    }

    /// Names the screen in the toolbar. The resource's own name heads the screen below it.
    private var title: String {
        switch previewPlace {
        case .board: "Previews"
        case .preview(let number): "PR #\(number)"
        case nil: openDeployment == nil ? resource.kind.title : "Deployment"
        }
    }

    /// Where the toolbar's back button leads from the screen on show: one step out, innermost first.
    private var currentBack: DetailBack? {
        switch previewPlace {
        case .preview(let number):
            if followedPreviewDeployment != nil {
                return DetailBack(title: "PR #\(number)") { followedPreviewDeployment = nil }
            }
            return DetailBack(title: "Previews") { previewPlace = .board }
        case .board:
            return DetailBack(title: resource.name) { previewPlace = nil }
        case nil:
            if openDeployment != nil {
                return DetailBack(title: "Deployments") { selectedDeployment = nil }
            }
            return back
        }
    }

    var body: some View {
        ZStack {
            if previewPlace != nil, case .application(let uuid) = resource.route {
                PreviewSpace(
                    resourceName: resource.name,
                    application: uuid,
                    previews: previews,
                    model: previewsModel,
                    client: deploymentClient,
                    place: $previewPlace,
                    followedDeployment: $followedPreviewDeployment,
                    // Every poll sets `isLoading`. Only the first load, before any history, should show a spinner.
                    isLoading: isLoading && deployments.isEmpty,
                    canLoadMore: canLoadMoreDeployments,
                    onLoadMore: onLoadMoreDeployments,
                    onDeploy: { showsPreviewDeployment = true }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                production
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: previewPlace == nil)
        // A restart or deploy started anywhere puts saved variables and settings to use.
        .onChange(of: pendingAction) { _, action in
            if action == .start || action == .deploy || action == .restart {
                variables.hasUnappliedChanges = false
                configuration.hasUnappliedChanges = false
            }
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .replacesSystemBack(currentBack != nil)
        .toolbar {
            DetailNavigation(title: title, back: currentBack)
            #if os(macOS)
            if let menuBar, menuBar.enabled {
                ToolbarItem(placement: .primaryAction) {
                    MenuBarWatchButton(model: menuBar, resource: resource)
                }
            }
            #endif
            if resource.kind == .application {
                ToolbarItem(placement: .primaryAction) {
                    PreviewsMenu(
                        resourceName: resource.name,
                        previews: previews,
                        isShowingPreviews: previewPlace != nil,
                        canDeploy: deploymentClient != nil,
                        onDeploy: { showsPreviewDeployment = true },
                        onShow: { place in
                            followedPreviewDeployment = nil
                            previewPlace = place
                        },
                        onGitHubAccess: { showsGitHubAccess = true }
                    )
                }
            }
            ToolbarItem(placement: .primaryAction) {
                ResourceGuideButton(kind: resource.kind)
            }
        }
        .sheet(isPresented: $showsPreviewDeployment) {
            if case .application(let uuid) = resource.route {
                let generation = previewGeneration
                PreviewDeploymentSheet(
                    client: deploymentClient, application: uuid, previews: previews, resourceName: resource.name
                ) {
                    queued, number in
                    guard generation == previewGeneration else { return }
                    followedPreviewDeployment = previewsModel.noteQueued(queued, number: number)
                    previewPlace = .preview(number)
                }
                .id(uuid)
            }
        }
        .sheet(isPresented: $showsGitHubAccess) {
            GitHubAccessSheet(repository: previewsModel.repository) {
                Task { await previewsModel.load() }
            }
        }
        .onChange(of: resource.route) { _, _ in
            previewGeneration += 1
            showsPreviewDeployment = false
            selectedDeployment = nil
            previewPlace = nil
            followedPreviewDeployment = nil
        }
        .stopConfirmation(for: $stopCandidate) { _ in
            onAction(.stop)
        }
    }

    /// The resource itself: its header, actions, and tabs.
    private var production: some View {
        VStack(alignment: .leading, spacing: 0) {
            ResourceHeader(
                resource: resource,
                pendingAction: pendingAction,
                lastDeploymentFailed: lastDeploymentFailed,
                onOpenProject: onOpenProject,
                onAction: { action in
                    if action == .stop {
                        stopCandidate = resource
                    } else {
                        onAction(action)
                    }
                }
            )
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 18)

            VStack(spacing: 8) {
                if let loadError {
                    NoticeBanner(message: loadError)
                }
                if let actionError {
                    NoticeBanner(message: actionError)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, loadError == nil && actionError == nil ? 0 : 12)

            if tabs.count > 1 {
                Picker("Show", selection: Binding(get: { currentTab }, set: { tab = $0 })) {
                    ForEach(tabs) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
            }

            Group {
                switch currentTab {
                case .deployments:
                    // Its own container, so the slide only runs between the timeline and a deployment.
                    // Switching tabs inserts the container, which fades like every other tab.
                    ZStack {
                        if let selectedDeployment {
                            DeploymentDetail(client: deploymentClient, initial: selectedDeployment)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        } else {
                            DeploymentTimeline(
                                deployments: deployments,
                                isLoading: isLoading,
                                onSelect: { selectedDeployment = $0 },
                                canLoadMore: canLoadMoreDeployments,
                                onLoadMore: onLoadMoreDeployments,
                                onShowPreviews: { previewPlace = .board }
                            )
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                    }
                case .backups:
                    if case .database(let uuid) = resource.route {
                        BackupsView(client: deploymentClient, database: uuid, resourceName: resource.name)
                    }
                case .containers:
                    ContainerList(containers: resource.containers)
                case .variables:
                    VariableList(
                        model: variables,
                        resource: resource,
                        pendingAction: pendingAction,
                        onAction: onAction
                    )
                case .settings:
                    ConfigurationView(
                        model: configuration,
                        resource: resource,
                        pendingAction: pendingAction,
                        onAction: onAction
                    )
                case .logs:
                    LogView(
                        lines: logLines,
                        rawLogs: rawLogs,
                        isLoading: isLoading,
                        lineCount: $logLineCount,
                        sources: resource.containers,
                        sourceID: Binding(get: { logContainer?.id }, set: { chosenContainerID = $0 }),
                        pausedMessage: pausedMessage
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
        .animation(.snappy, value: currentTab)
        .animation(reduceMotion ? nil : .snappy, value: selectedDeployment)
        .animation(.snappy, value: loadError)
        .animation(.snappy, value: actionError)
    }
}

/// The views under the detail header.
enum DetailTab: Identifiable, Hashable {
    case backups
    case deployments
    case containers
    case logs
    case variables
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .backups: "Backups"
        case .deployments: "Deployments"
        case .containers: "Containers"
        case .logs: "Logs"
        case .variables: "Variables"
        case .settings: "Settings"
        }
    }
}

#Preview("Application") {
    NavigationStack {
        applicationDetailPreview()
    }
    .frame(width: 640, height: 720)
    .environment(VariableLock(isRequired: true))
}

#Preview("Service") {
    NavigationStack {
        ResourceDetailScreen(
            client: nil,
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
            pendingAction: nil,
            onAction: { _ in }
        )
    }
    .frame(width: 640, height: 720)
    .environment(VariableLock(isRequired: true))
}

#Preview("Database") {
    NavigationStack {
        databaseDetailPreview()
    }
    .frame(width: 640, height: 720)
    .environment(VariableLock(isRequired: true))
}

private func applicationDetailPreview() -> some View {
    let model = ResourceDetailModel()
    model.logs = "2026-09-29T08:00:00Z listening on 3000\n2026-09-29T08:00:01Z ready"
    model.deployments = [
        DeploymentLine(
            id: "prod",
            status: "finished",
            commit: "abc1234",
            message: "fix: login redirect",
            startedAt: .now.addingTimeInterval(-600),
            finishedAt: .now.addingTimeInterval(-540)
        ),
        DeploymentLine(
            id: "preview",
            status: "finished",
            commit: "def5678",
            pullRequest: 18,
            url: URL(string: "https://pr-18.example.com")
        ),
    ]
    return ResourceDetailScreen(
        client: nil,
        resource: ResourceSummary(
            route: .application("app"),
            name: "marketing-site",
            status: "running:healthy",
            link: URL(string: "https://hotify.example.com")
        ),
        pendingAction: nil,
        model: model,
        onAction: { _ in }
    )
}

private func databaseDetailPreview() -> some View {
    let model = ResourceDetailModel()
    model.logs = "2026-09-29T08:00:00Z database system is ready to accept connections"
    return ResourceDetailScreen(
        client: nil,
        resource: ResourceSummary(route: .database("db"), name: "postgres", status: "exited"),
        pendingAction: nil,
        model: model,
        onAction: { _ in }
    )
}

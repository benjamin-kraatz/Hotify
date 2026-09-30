import CoolifyAPI
import SwiftUI

/// Deployments, containers, logs, and variables for one application, database, or service. Polls while it is on screen.
struct ResourceDetailScreen: View {
    var client: CoolifyClient?
    var resource: ResourceSummary
    var pendingAction: ResourceAction?
    /// The last action that failed, from the dashboard. The middle column is off screen on iPhone.
    var actionError: String?
    var onAction: (ResourceAction) -> Void

    @State private var model: ResourceDetailModel
    @State private var variables: VariablesModel
    @State private var chosenContainerID: Int?

    init(
        client: CoolifyClient?,
        resource: ResourceSummary,
        pendingAction: ResourceAction?,
        actionError: String? = nil,
        model: ResourceDetailModel = ResourceDetailModel(),
        variables: VariablesModel = VariablesModel(),
        onAction: @escaping (ResourceAction) -> Void
    ) {
        self.client = client
        self.resource = resource
        self.pendingAction = pendingAction
        self.actionError = actionError
        self.onAction = onAction
        _model = State(initialValue: model)
        _variables = State(initialValue: variables)
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
            logLines: model.logLines,
            rawLogs: model.logs,
            logLineCount: $model.logLineCount,
            deployments: model.deployments,
            variables: variables,
            loadError: model.loadError,
            actionError: actionError,
            isLoading: model.isLoading,
            deploymentClient: client,
            canLoadMoreDeployments: model.canLoadMoreDeployments,
            onLoadMoreDeployments: {
                model.deploymentLimit += 20
                Task { await model.refresh() }
            },
            onAction: onAction
        )
        .task(id: resource.route) {
            guard let client else { return }
            model.prepare(client, route: resource.route)
            variables.prepare(client, route: resource.route)
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
    }
}

/// The detail layout. Takes plain values, and models without a client, so a preview does not need one.
struct ResourceDetail: View {
    var resource: ResourceSummary
    var pendingAction: ResourceAction?
    var logContainer: ContainerSummary?
    @Binding var chosenContainerID: Int?
    var logLines: [LogLine]
    var rawLogs: String
    @Binding var logLineCount: Int
    var deployments: [DeploymentLine]
    var variables: VariablesModel
    var loadError: String?
    var actionError: String?
    var isLoading: Bool
    var deploymentClient: CoolifyClient?
    var canLoadMoreDeployments = false
    var onLoadMoreDeployments: () -> Void = {}
    var onAction: (ResourceAction) -> Void

    #if os(macOS)
    /// Missing in previews, which leaves the menu bar button out.
    @SwiftUI.Environment(MenuBarModel.self) private var menuBar: MenuBarModel?
    #endif
    @State private var selectedDeployment: DeploymentLine?
    @State private var tab: DetailTab?
    @State private var stopCandidate: ResourceSummary?
    @State private var showsPreviewDeployment = false
    @State private var previewGeneration = 0
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tabs: [DetailTab] {
        switch resource.kind {
        case .application: [.logs, .deployments, .variables]
        case .service: [.logs, .containers, .variables]
        case .database: [.logs, .backups, .variables]
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ResourceHeader(
                resource: resource,
                pendingAction: pendingAction,
                lastDeploymentFailed: lastDeploymentFailed,
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

            if resource.kind == .application {
                HStack {
                    Button("Deploy Preview…", systemImage: "arrow.triangle.pull") {
                        showsPreviewDeployment = true
                    }
                    .glassButton()
                    .disabled(deploymentClient == nil || pendingAction != nil)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
            }

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
                            DeploymentDetail(client: deploymentClient, initial: selectedDeployment) {
                                self.selectedDeployment = nil
                            }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        } else {
                            DeploymentTimeline(
                                deployments: deployments,
                                isLoading: isLoading,
                                onSelect: { selectedDeployment = $0 },
                                canLoadMore: canLoadMoreDeployments,
                                onLoadMore: onLoadMoreDeployments
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
        // A restart or deploy started anywhere puts saved variable changes to use.
        .onChange(of: pendingAction) { _, action in
            if action == .start || action == .deploy || action == .restart {
                variables.hasUnappliedChanges = false
            }
        }
        #if os(macOS)
        .navigationTitle(resource.name)
        #else
        .navigationTitle(resource.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(macOS)
            if let menuBar, menuBar.enabled {
                ToolbarItem(placement: .primaryAction) {
                    MenuBarWatchButton(model: menuBar, resource: resource)
                }
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                ResourceGuideButton(kind: resource.kind)
            }
        }
        .sheet(isPresented: $showsPreviewDeployment) {
            if case .application(let uuid) = resource.route {
                let generation = previewGeneration
                PreviewDeploymentSheet(
                    client: deploymentClient, application: uuid, previousPRs: deployments.compactMap(\.pullRequest),
                    resourceName: resource.name
                ) {
                    queued, number in
                    guard generation == previewGeneration else { return }
                    tab = .deployments
                    selectedDeployment = DeploymentLine(
                        id: queued.deploymentUUID ?? "",
                        status: "queued",
                        pullRequest: number,
                        startedAt: .now
                    )
                }
                .id(uuid)
            }
        }
        .onChange(of: resource.route) { _, _ in
            previewGeneration += 1
            showsPreviewDeployment = false
            selectedDeployment = nil
        }
        .stopConfirmation(for: $stopCandidate) { _ in
            onAction(.stop)
        }
    }
}

/// The views under the detail header.
enum DetailTab: Identifiable, Hashable {
    case backups
    case deployments
    case containers
    case logs
    case variables

    var id: Self { self }

    var title: String {
        switch self {
        case .backups: "Backups"
        case .deployments: "Deployments"
        case .containers: "Containers"
        case .logs: "Logs"
        case .variables: "Variables"
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

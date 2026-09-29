import CoolifyAPI
import SwiftUI

/// Deployments, containers, and logs for one application, database, or service. Polls while it is on screen.
struct ResourceDetailScreen: View {
    var client: CoolifyClient?
    var resource: ResourceSummary
    var pendingAction: ResourceAction?
    /// The last action that failed, from the dashboard. The middle column is off screen on iPhone.
    var actionError: String?
    var onAction: (ResourceAction) -> Void

    @State private var model: ResourceDetailModel
    @State private var chosenContainerID: Int?

    init(
        client: CoolifyClient?,
        resource: ResourceSummary,
        pendingAction: ResourceAction?,
        actionError: String? = nil,
        model: ResourceDetailModel = ResourceDetailModel(),
        onAction: @escaping (ResourceAction) -> Void
    ) {
        self.client = client
        self.resource = resource
        self.pendingAction = pendingAction
        self.actionError = actionError
        self.onAction = onAction
        _model = State(initialValue: model)
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
            loadError: model.loadError,
            actionError: actionError,
            isLoading: model.isLoading,
            onAction: onAction
        )
        .task(id: resource.route) {
            guard let client else { return }
            model.prepare(client, route: resource.route)
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

/// The detail layout. Takes plain values so a preview does not need a client.
struct ResourceDetail: View {
    var resource: ResourceSummary
    var pendingAction: ResourceAction?
    var logContainer: ContainerSummary?
    @Binding var chosenContainerID: Int?
    var logLines: [LogLine]
    var rawLogs: String
    @Binding var logLineCount: Int
    var deployments: [DeploymentLine]
    var loadError: String?
    var actionError: String?
    var isLoading: Bool
    var onAction: (ResourceAction) -> Void

    @State private var tab: DetailTab?
    @State private var stopCandidate: ResourceSummary?

    private var tabs: [DetailTab] {
        switch resource.kind {
        case .application: [.logs, .deployments]
        case .service: [.logs, .containers]
        case .database: [.logs]
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

            VStack(alignment: .leading, spacing: 6) {
                if tabs.count > 1 {
                    Picker("Show", selection: Binding(get: { currentTab }, set: { tab = $0 })) {
                        ForEach(tabs) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Text(currentTab.caption(for: resource.kind))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Group {
                switch currentTab {
                case .deployments:
                    DeploymentTimeline(deployments: deployments, isLoading: isLoading)
                case .containers:
                    ContainerList(containers: resource.containers)
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
        .animation(.snappy, value: loadError)
        .animation(.snappy, value: actionError)
        #if os(macOS)
        .navigationTitle(resource.name)
        #else
        .navigationTitle(resource.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .stopConfirmation(for: $stopCandidate) { _ in
            onAction(.stop)
        }
    }
}

/// The views under the detail header.
enum DetailTab: Identifiable, Hashable {
    case deployments
    case containers
    case logs

    var id: Self { self }

    var title: String {
        switch self {
        case .deployments: "Deployments"
        case .containers: "Containers"
        case .logs: "Logs"
        }
    }

    /// One line on what the tab holds, because "Deployments" next to a Redeploy button reads like an action.
    func caption(for kind: ResourceKind) -> String {
        switch (self, kind) {
        case (.deployments, _):
            "Each build Coolify ran for this app, newest first. Start, Redeploy, and Restart each add one."
        case (.containers, _):
            "The containers this service runs, and how each one is doing."
        case (.logs, .service):
            "What one container prints, newest at the bottom. Pick the container on the left."
        case (.logs, _):
            "What the container prints, newest at the bottom. Refreshes every 5 seconds."
        }
    }
}

#Preview("Application") {
    NavigationStack {
        applicationDetailPreview()
    }
    .frame(width: 640, height: 720)
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
}

#Preview("Database") {
    NavigationStack {
        databaseDetailPreview()
    }
    .frame(width: 640, height: 720)
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

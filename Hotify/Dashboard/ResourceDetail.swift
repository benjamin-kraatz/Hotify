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
    /// Leaves the detail column after Coolify deletes the resource.
    var onDeleted: () -> Void

    @State private var model: ResourceDetailModel
    @State private var variables: VariablesModel
    @State private var configuration: ConfigurationModel
    @State private var previews = PreviewsModel()
    @State private var rollback = RollbackModel()
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
        onAction: @escaping (ResourceAction) -> Void,
        onDeleted: @escaping () -> Void = {}
    ) {
        self.client = client
        self.resource = resource
        self.pendingAction = pendingAction
        self.actionError = actionError
        self.back = back
        self.onOpenProject = onOpenProject
        self.onAction = onAction
        self.onDeleted = onDeleted
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
        case .backups:
            _tab = State(initialValue: .backups)
        case .deployment:
            _tab = State(initialValue: .deployments)
        case .rollback, nil:
            break
        }
        opening = entry?.place
    }

    /// Where a link asked the screen to open, for the detail to act on once.
    private let opening: ResourceEntry.Place?

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
            rollbackModel: rollback,
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
            opening: opening,
            onVersionChanged: {
                Task {
                    await model.refresh()
                    await rollback.load()
                    await configuration.load()
                }
            },
            onAction: onAction,
            onDeleted: onDeleted
        )
        .task(id: resource.route) {
            guard let client else { return }
            model.prepare(client, route: resource.route)
            variables.prepare(client, route: resource.route)
            configuration.prepare(client, route: resource.route)
            previews.prepare(client, route: resource.route)
            rollback.prepare(client, route: resource.route)
            Task { await previews.load() }
            Task { await rollback.load() }
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
        // Pick up the finished deployment now rather than on the next poll. A finished build also leaves a new image.
        .onChange(of: resource.isDeploying) { _, _ in
            Task { await model.refresh() }
            Task { await rollback.load() }
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
    var rollbackModel = RollbackModel()
    var loadError: String?
    var actionError: String?
    var isLoading: Bool
    var deploymentClient: CoolifyClient?
    var canLoadMoreDeployments = false
    var onLoadMoreDeployments: () -> Void = {}
    /// Where back leads from the resource's own screen. `nil` when the resource is the top of the column.
    var back: DetailBack?
    var onOpenProject: (() -> Void)?
    /// A deployment to open, or a rollback to ask about, when the screen appears. A notification's link sets it.
    var opening: ResourceEntry.Place?
    /// Reloads the history, the images, and the settings once a rollback or another version queued.
    var onVersionChanged: () -> Void = {}
    var onAction: (ResourceAction) -> Void
    /// Leaves the detail column after Coolify deletes the resource.
    var onDeleted: () -> Void = {}

    #if os(macOS)
    /// Missing in previews, which leaves the menu bar button out.
    @SwiftUI.Environment(MenuBarModel.self) private var menuBar: MenuBarModel?
    #endif
    @State private var selectedDeployment: DeploymentLine?
    @State private var stopCandidate: ResourceSummary?
    @State private var rollbackCandidate: RollbackCandidate?
    /// The iPhone's deployment sheet asks on its own, since a dialog on the screen under it can't show.
    @State private var sheetRollbackCandidate: RollbackCandidate?
    @State private var showsDeployVersion = false
    /// A rollback the Deploy a Version sheet handed over. It asks once the sheet is gone.
    @State private var rollbackAfterSheet: RollbackCandidate?
    /// Something about the last version deployed that the user should know, such as a pin that stayed.
    @State private var versionNotice: String?
    @State private var didOpen = false
    /// The deployment a link opened to have explained.
    @State private var explainedDeploymentID: String?
    /// Set by a link to roll back, until the images arrive to pick from.
    @State private var wantsRollback = false
    @State private var showsPreviewDeployment = false
    @State private var showsGitHubAccess = false
    @State private var showsRemoval = false
    @State private var isRemoving = false
    @State private var removalError: String?
    /// A new value gives the confirmation fresh switches, so volumes start off every time it opens.
    @State private var removalPresentation = 0
    @State private var previewGeneration = 0
    @State private var followedPreviewDeployment: DeploymentLine?
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tabs: [DetailTab] {
        switch resource.kind {
        case .application: [.logs, .deployments, .tasks, .storage, .variables, .settings]
        case .service: [.logs, .containers, .tasks, .storage, .variables, .settings]
        case .database: [.logs, .backups, .storage, .variables, .settings]
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

    /// The Mac opens a deployment in the column, in place of the timeline. An iPhone has room for only half of it
    /// there, under the resource's header, so it opens the deployment in a sheet of its own.
    private static var opensDeploymentInColumn: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// The deployment whose build output is in the column, which takes the back button until it closes.
    private var openDeployment: DeploymentLine? {
        Self.opensDeploymentInColumn && currentTab == .deployments ? selectedDeployment : nil
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
        .toolbar { toolbarContent }
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
        .sheet(
            isPresented: $showsDeployVersion,
            onDismiss: {
                // A dialog can't show while the sheet leaves, so the handed-over rollback asks afterwards.
                rollbackCandidate = rollbackAfterSheet
                rollbackAfterSheet = nil
            }
        ) {
            if case .application(let uuid) = resource.route {
                DeployVersionSheet(
                    model: DeployVersionModel(client: deploymentClient, application: uuid),
                    resourceName: resource.name,
                    keptImages: rollbackModel.images,
                    onRollBack: { image in
                        rollbackAfterSheet = RollbackCandidate(image: image, resourceName: resource.name)
                    },
                    onDeployed: { deployed, version in deployedVersion(deployed, version) }
                )
                .id(uuid)
            }
        }
        .onChange(of: resource.route) { _, _ in
            previewGeneration += 1
            showsPreviewDeployment = false
            selectedDeployment = nil
            previewPlace = nil
            followedPreviewDeployment = nil
            rollbackCandidate = nil
            sheetRollbackCandidate = nil
            showsDeployVersion = false
            rollbackAfterSheet = nil
            versionNotice = nil
            showsRemoval = false
            removalError = nil
        }
        .stopConfirmation(for: $stopCandidate) { _ in
            onAction(.stop)
        }
        .task { followOpening() }
        .onChange(of: rollbackModel.hasLoaded) { _, _ in askRollbackIfWanted() }
        .rollbackConfirmation(for: $rollbackCandidate) { image in
            rollBack(to: image)
        }
        #if os(iOS)
        .sheet(item: $selectedDeployment) { deployment in
            NavigationStack {
                DeploymentDetail(
                    client: deploymentClient, initial: deployment,
                    explainsOnLoad: explainedDeploymentID == deployment.id
                )
                .padding(.top, 8)
                .navigationTitle("Deployment")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            selectedDeployment = nil
                        }
                    }
                    if let image = rollbackTarget(for: deployment) {
                        ToolbarItem(placement: .primaryAction) {
                            rollBackToThisButton(image) { sheetRollbackCandidate = $0 }
                        }
                    }
                }
            }
            .rollbackConfirmation(for: $sheetRollbackCandidate) { image in
                rollBack(to: image)
            }
            .presentationDetents([.large])
        }
        #endif
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
        if resource.kind == .application, previewPlace == nil {
            if let openDeployment, let image = rollbackTarget(for: openDeployment) {
                ToolbarItem(placement: .primaryAction) {
                    rollBackToThisButton(image) { rollbackCandidate = $0 }
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    VersionsMenu(
                        images: rollbackModel.images,
                        hasLoaded: rollbackModel.hasLoaded,
                        loadError: rollbackModel.loadError,
                        deployments: deployments,
                        isBusy: rollbackModel.isRollingBack || deploymentClient == nil,
                        onChoose: { image in
                            rollbackCandidate = RollbackCandidate(image: image, resourceName: resource.name)
                        },
                        onDeployVersion: { showsDeployVersion = true }
                    )
                }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Delete", systemImage: "trash") {
                removalError = nil
                removalPresentation += 1
                showsRemoval = true
            }
            .disabled(deploymentClient == nil)
            .help("Delete \(resource.name)")
            .popover(isPresented: $showsRemoval, arrowEdge: .bottom) {
                ResourceRemovalDialog(
                    name: resource.name,
                    isDeleting: isRemoving,
                    error: removalError,
                    onDelete: { options in
                        Task { await remove(options) }
                    },
                    onCancel: {
                        removalError = nil
                        showsRemoval = false
                    }
                )
                .id(removalPresentation)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            ResourceGuideButton(kind: resource.kind)
        }
    }

    /// Asks Coolify to delete the resource, then leaves the detail column.
    private func remove(_ options: RemovalOptions) async {
        guard let deploymentClient, !isRemoving else { return }
        isRemoving = true
        removalError = nil
        defer { isRemoving = false }
        do {
            _ = try await deploymentClient.deleteResource(resource.route.uuid, kind: removalKind, options: options)
            showsRemoval = false
            onDeleted()
        } catch {
            removalError = (error as? CoolifyError)?.summary ?? error.localizedDescription
        }
    }

    private var removalKind: RemovalKind {
        switch resource.kind {
        case .application: .application
        case .database: .database
        case .service: .service
        }
    }

    /// Acts once on where a link asked to open: a deployment, maybe explained, or the rollback confirmation.
    private func followOpening() {
        guard !didOpen, let opening else { return }
        didOpen = true
        switch opening {
        case .deployment(let id, let explains):
            selectedDeployment = DeploymentLine(id: id, status: "unknown")
            explainedDeploymentID = explains ? id : nil
        case .rollback:
            wantsRollback = true
            askRollbackIfWanted()
        case .deployments, .previews, .backups:
            break
        }
    }

    /// Asks to roll back to the newest image before the running one, once Coolify listed them.
    private func askRollbackIfWanted() {
        guard wantsRollback, rollbackModel.hasLoaded else { return }
        wantsRollback = false
        if let image = rollbackModel.images.first(where: { !$0.isCurrent }) {
            rollbackCandidate = RollbackCandidate(image: image, resourceName: resource.name)
        } else {
            versionNotice = "Coolify kept no earlier image of \(resource.name) to roll back to."
        }
    }

    /// The kept image a production deployment built, unless it is the one running.
    private func rollbackTarget(for line: DeploymentLine) -> RollbackImage? {
        guard deploymentClient != nil, let image = rollbackModel.image(for: line), !image.isCurrent else { return nil }
        return image
    }

    private func rollBackToThisButton(_ image: RollbackImage, ask: @escaping (RollbackCandidate) -> Void)
        -> some View
    {
        Button("Roll Back to This…", systemImage: "arrow.uturn.backward") {
            ask(RollbackCandidate(image: image, resourceName: resource.name))
        }
        .help("Run the image Coolify kept from this deployment")
        .disabled(rollbackModel.isRollingBack)
    }

    /// Queues the rollback, then opens the deployment it started in place of the one on screen.
    private func rollBack(to image: RollbackImage) {
        Task {
            guard let deployment = await rollbackModel.rollBack(to: image) else { return }
            open(queued: deployment, commit: image.isCommit ? image.tag : nil, isRollback: true)
        }
    }

    /// Opens the deployment a version started, and says so when Coolify kept the version pinned after deploying once.
    private func deployedVersion(_ deployed: DeployedVersion, _ version: ApplicationVersion) {
        if case .commit(let sha) = version {
            open(queued: deployed.deploymentUUID, commit: sha, isRollback: false)
        } else {
            open(queued: deployed.deploymentUUID, commit: nil, isRollback: false)
        }
        versionNotice = deployed.restoreError.map {
            "The deployment is queued, but \(resource.name) stays pinned to this version. \($0) Change it in Settings."
        }
    }

    /// Opens a deployment that just queued, in place of the one on screen, and reloads what it changes.
    private func open(queued deployment: String, commit: String?, isRollback: Bool) {
        let built = commit.flatMap { commit in
            deployments.first { !$0.isPreview && RollbackImage(tag: commit).matches(commit: $0.commitSHA ?? $0.commit) }
        }
        let isSHA = commit.map { $0.count >= 7 && $0.allSatisfy(\.isHexDigit) } ?? false
        tab = .deployments
        selectedDeployment = DeploymentLine(
            id: deployment,
            status: "queued",
            commit: isSHA ? commit.map { String($0.prefix(7)) } : nil,
            commitSHA: isSHA ? commit : nil,
            message: built?.message,
            isRollback: isRollback,
            startedAt: .now
        )
        onVersionChanged()
    }

    /// The resource itself: its header, actions, and tabs.
    private var production: some View {
        VStack(alignment: .leading, spacing: 0) {
            ResourceHeader(
                resource: resource,
                pendingAction: pendingAction,
                lastDeploymentFailed: lastDeploymentFailed,
                onOpenProject: onOpenProject,
                onShowSource: resource.kind == .application ? { tab = .settings } : nil,
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
                if let rollbackError = rollbackModel.error {
                    NoticeBanner(message: rollbackError)
                }
                if let versionNotice {
                    NoticeBanner(message: versionNotice)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, hasBanner ? 12 : 0)

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
                        if let openDeployment {
                            DeploymentDetail(
                                client: deploymentClient, initial: openDeployment,
                                explainsOnLoad: explainedDeploymentID == openDeployment.id
                            )
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        } else {
                            DeploymentTimeline(
                                deployments: deployments,
                                isLoading: isLoading,
                                onSelect: { selectedDeployment = $0 },
                                canLoadMore: canLoadMoreDeployments,
                                onLoadMore: onLoadMoreDeployments,
                                onShowPreviews: { previewPlace = .board },
                                rollbackImages: deploymentClient == nil ? [] : rollbackModel.images,
                                onRollBack: { image in
                                    rollbackCandidate = RollbackCandidate(image: image, resourceName: resource.name)
                                }
                            )
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                    }
                case .tasks:
                    switch resource.route {
                    case .application(let uuid):
                        TasksView(client: deploymentClient, uuid: uuid, kind: .application)
                    case .service(let uuid):
                        TasksView(client: deploymentClient, uuid: uuid, kind: .service)
                    case .database:
                        EmptyView()
                    }
                case .backups:
                    if case .database(let uuid) = resource.route {
                        BackupsView(client: deploymentClient, database: uuid, resourceName: resource.name)
                    }
                case .storage:
                    StorageList(client: deploymentClient, route: resource.route, resourceName: resource.name)
                case .containers:
                    ContainerList(
                        containers: resource.containers,
                        client: deploymentClient,
                        serviceUUID: resource.kind == .service ? resource.route.uuid : nil
                    )
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
        .animation(.snappy, value: rollbackModel.error)
        .animation(.snappy, value: versionNotice)
    }

    private var hasBanner: Bool {
        loadError != nil || actionError != nil || rollbackModel.error != nil || versionNotice != nil
    }
}

/// The views under the detail header.
enum DetailTab: Identifiable, Hashable {
    case backups
    case storage
    case deployments
    case tasks
    case containers
    case logs
    case variables
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .backups: "Backups"
        case .storage: "Storage"
        case .deployments: "Deployments"
        case .tasks: "Tasks"
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

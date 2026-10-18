import CoolifyAPI
import SwiftUI

/// From template, or a compose file the user writes, to running service in one sheet: create, set up, start. A
/// database skips setup, since Coolify starts it as it creates it. An application does too, and can deploy as soon
/// as it exists.
///
/// On the Mac and iPad, choosing, placing, and naming share one screen of three columns, so nothing is created on a
/// screen of its own. On iPhone the gallery pushes the screen that creates what was chosen, and going back is the
/// system's own back button and swipe. Setup and the first start are screens pushed onto the sheet's navigation
/// stack. The service only exists in Coolify once the user creates it. From there the screens hide their way back,
/// and closing the sheet keeps or deletes the service on purpose.
struct ProvisioningSheet: View {
    var client: CoolifyClient?
    var instanceID: UUID?
    /// The project page the sheet opened from, which the placement pickers start at.
    var hint: PlacementHint?
    var catalog: TemplateCatalog
    /// Closes the sheet and opens the new service, or opens nothing.
    var onClose: (ResourceRoute?) -> Void

    @State private var model: ProvisioningModel
    @State private var databases: DatabaseProvisioningModel
    @State private var applications: ApplicationProvisioningModel
    @State private var path: [ProvisioningRoute] = []
    #if os(iOS)
    @SwiftUI.Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    init(
        client: CoolifyClient?,
        instanceID: UUID?,
        hint: PlacementHint? = nil,
        catalog: TemplateCatalog,
        model: ProvisioningModel = ProvisioningModel(),
        onClose: @escaping (ResourceRoute?) -> Void
    ) {
        self.client = client
        self.instanceID = instanceID
        self.hint = hint
        self.catalog = catalog
        self.onClose = onClose
        _model = State(initialValue: model)
        _databases = State(initialValue: DatabaseProvisioningModel(placement: model.placement))
        _applications = State(initialValue: ApplicationProvisioningModel(placement: model.placement))
    }

    private var models: NewResourceModels {
        NewResourceModels(services: model, databases: databases, applications: applications)
    }

    /// Three columns where there is room for them. An iPhone, or an iPad in a narrow split, gets the list.
    private var usesWorkbench: Bool {
        #if os(macOS)
        true
        #else
        sizeClass == .regular
        #endif
    }

    var body: some View {
        NavigationStack(path: $path) {
            root
                .navigationDestination(for: ProvisioningRoute.self) { route in
                    destination(route)
                }
        }
        .tint(.ember)
        // Creating and starting move the sheet on by themselves. The stages only ever go forward.
        .onChange(of: model.stage) { _, stage in
            switch stage {
            case .choosing: break
            case .settingUp: path.append(.setUp)
            case .starting: path.append(.start)
            }
        }
        .onChange(of: databases.created) { _, created in
            if created != nil { path.append(.databaseStart) }
        }
        .onChange(of: applications.created) { _, created in
            if created != nil { path.append(.applicationStart) }
        }
        // Only the first screen closes with a swipe. On a launch pad the user may have named and placed the service,
        // which a stray swipe would lose. Once the service exists, closing has to keep or delete it, which setup asks
        // about.
        .interactiveDismissDisabled(!path.isEmpty || models.isCreating)
        #if os(macOS)
        .frame(minWidth: 1020, idealWidth: 1200, minHeight: 600, idealHeight: 740)
        #endif
        .task {
            model.prepare(client, instanceID: instanceID, hint: hint)
            databases.prepare(client)
            applications.prepare(client)
            async let templates: Void = catalog.load()
            async let placement: Void = model.placement.load()
            _ = await (templates, placement)
        }
    }

    @ViewBuilder
    private var root: some View {
        if usesWorkbench {
            ProvisioningWorkbench(
                models: models, catalog: catalog, instanceRoot: model.instanceRoot, onCancel: { onClose(nil) }
            )
            .navigationTitle("New Resource")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        } else {
            CatalogGallery(
                shelves: catalog.shelves,
                instanceRoot: model.instanceRoot,
                isLoading: catalog.isLoading,
                loadError: catalog.loadError,
                onRetry: { Task { await catalog.refresh() } },
                onSelect: { entry in
                    models.choose(entry, catalog: catalog)
                    path.append(entry.route)
                }
            )
            .navigationTitle("New Resource")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onClose(nil) }
                        .disabled(models.isCreating)
                }
            }
        }
    }

    @ViewBuilder
    private func destination(_ route: ProvisioningRoute) -> some View {
        switch route {
        case .template(let template):
            TemplateLaunchPad(template: template, model: model, instanceRoot: model.instanceRoot)
                .provisioningStep(.create)
                .navigationTitle(template.displayName)
                #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
                #endif
                // Creating is under way, and its result decides where the sheet goes next.
                .navigationBarBackButtonHidden(model.isCreating)
        case .compose:
            ComposeLaunchPad(model: model, instanceRoot: model.instanceRoot)
                .provisioningStep(.create)
                .navigationTitle("Docker Compose")
                #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
                #endif
                .navigationBarBackButtonHidden(model.isCreating)
        case .setUp:
            ServiceSetup(model: model, onClose: onClose)
                .provisioningStep(.setUp)
        case .start:
            IgnitionView(
                name: model.serviceName,
                ignition: model.ignition,
                addresses: addresses,
                onOpen: { onClose(model.route) },
                onClose: { onClose(nil) }
            )
            .task { await model.watch() }
            .provisioningStep(.start, isFinished: model.ignition.phase == .running)
        case .database(let engine):
            DatabaseLaunchPad(engine: engine, model: databases, instanceRoot: model.instanceRoot)
                .provisioningStep(.create, steps: ProvisioningStep.instant)
                .navigationTitle(engine.displayName)
                #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
                #endif
                .navigationBarBackButtonHidden(databases.isCreating)
        case .databaseStart:
            IgnitionView(
                name: databases.displayName,
                ignition: databases.ignition,
                addresses: [],
                isDatabase: true,
                onOpen: { onClose(databases.route) },
                onClose: { onClose(nil) }
            ) {
                ConnectionCard(
                    internalURL: databases.created?.internalURL, externalURL: databases.created?.externalURL)
            }
            .task { await databases.watch() }
            .provisioningStep(
                .start, isFinished: databases.ignition.phase == .running, steps: ProvisioningStep.instant)
        case .application(let source):
            ApplicationLaunchPad(source: source, model: applications, instanceRoot: model.instanceRoot)
                .provisioningStep(.create, steps: ProvisioningStep.instant)
                .navigationTitle(source.title)
                #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
                #endif
                .navigationBarBackButtonHidden(applications.isCreating)
        case .applicationStart:
            IgnitionView(
                name: applications.displayName,
                ignition: applications.ignition,
                addresses: [],
                isApplication: true,
                deploysNow: applications.instantDeploy,
                onOpen: { onClose(applications.route) },
                onClose: { onClose(nil) }
            )
            .task { await applications.watch() }
            .provisioningStep(
                .start,
                isFinished: !applications.instantDeploy || applications.ignition.phase == .running,
                steps: ProvisioningStep.instant
            )
        }
    }

    /// The service's public addresses, first one per container.
    private var addresses: [URL] {
        model.setup.domains.compactMap { domain in
            domain.trimmed.split(separator: ",").first.flatMap { URL(string: String($0)) }
        }
    }
}

/// A screen on the provisioning sheet's navigation stack.
enum ProvisioningRoute: Hashable {
    /// One template up close, where the service is placed, named, and created. Pushed on iPhone.
    case template(ServiceTemplate)
    /// A compose file the user writes, where the service is placed, named, and created like a template's.
    case compose
    /// The created service's domains and settings, before its first start.
    case setUp
    /// The first start, watched until the service runs.
    case start
    /// One database engine, where the database is placed, named, created, and started.
    case database(DatabaseEngine)
    /// A new database's first start, with how to connect to it.
    case databaseStart
    /// One application source, where it is placed, named, and created.
    case application(NewApplicationSource)
    /// A new application's first deploy, or the screen that opens it when it was left stopped.
    case applicationStart
}

extension View {
    /// Puts the row of step flames under the navigation bar, saying how far along the sheet is.
    fileprivate func provisioningStep(
        _ step: ProvisioningStep, isFinished: Bool = false, steps: [ProvisioningStep] = ProvisioningStep.allCases
    ) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            ProvisioningSteps(current: step, isFinished: isFinished, steps: steps)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.bar)
                .overlay(alignment: .bottom) { Divider() }
        }
    }
}

#Preview {
    ProvisioningSheet(
        client: nil,
        instanceID: nil,
        catalog: TemplateCatalog(templates: [
            ServiceTemplate(
                slug: "ghost", slogan: "A content management system and blogging platform.", category: "cms"),
            ServiceTemplate(slug: "n8n", slogan: "Workflow automation for technical people.", category: "automation"),
            ServiceTemplate(
                slug: "uptime-kuma", slogan: "A fancy self-hosted monitoring tool.", category: "monitoring"),
        ]),
        onClose: { _ in }
    )
}

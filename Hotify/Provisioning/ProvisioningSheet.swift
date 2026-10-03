import CoolifyAPI
import SwiftUI

/// From template to running service in one sheet: choose, place, set up, start. A database skips setup, since
/// Coolify starts it as it creates it.
///
/// Each step is a screen pushed onto the sheet's navigation stack, so going back from a template is the system's
/// own back button and swipe. The service only exists in Coolify once the user creates it on the second step.
/// From there the screens hide their way back, and closing the sheet keeps or deletes the service on purpose.
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
    @State private var kind = NewResourceKind.service
    @State private var path: [ProvisioningRoute] = []

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
    }

    var body: some View {
        NavigationStack(path: $path) {
            gallery
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
        // Only the gallery closes with a swipe. On a template the user may have named and placed the service, which
        // a stray swipe would lose. Once the service exists, closing has to keep or delete it, which setup asks about.
        .interactiveDismissDisabled(!path.isEmpty || model.isCreating || databases.isCreating)
        #if os(macOS)
        .frame(minWidth: 680, idealWidth: 860, minHeight: 600, idealHeight: 780)
        #endif
        .task {
            model.prepare(client, instanceID: instanceID, hint: hint)
            databases.prepare(client)
            async let templates: Void = catalog.load()
            async let placement: Void = model.placement.load()
            _ = await (templates, placement)
        }
    }

    @ViewBuilder
    private var gallery: some View {
        Group {
            switch kind {
            case .service: templates
            case .database:
                DatabaseGallery(instanceRoot: model.instanceRoot) { engine in
                    databases.createProblem = nil
                    path.append(.database(engine))
                }
            }
        }
        // In the content, not the toolbar: a Mac sheet's toolbar leaves out a principal item.
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Create", selection: $kind) {
                ForEach(NewResourceKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .provisioningStep(.choose, steps: kind.steps)
        .navigationTitle("New Resource")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onClose(nil) }
                    .disabled(model.isCreating || databases.isCreating)
            }
        }
    }

    private var templates: some View {
        TemplateGallery(
            shelves: catalog.shelves,
            instanceRoot: model.instanceRoot,
            isLoading: catalog.isLoading,
            loadError: catalog.loadError,
            onRetry: { Task { await catalog.refresh() } },
            onSelect: { template in
                model.createProblem = nil
                // Keep a name the user typed. One that is a template's slug was filled in here.
                if model.name.isEmpty || catalog.template(model.name) != nil {
                    model.name = template.slug
                }
                path.append(.template(template))
            }
        )
    }

    @ViewBuilder
    private func destination(_ route: ProvisioningRoute) -> some View {
        switch route {
        case .template(let template):
            TemplateLaunchPad(template: template, model: model, instanceRoot: model.instanceRoot)
                .provisioningStep(.place)
                .navigationTitle(template.displayName)
                #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
                #endif
                // Creating is under way, and its result decides where the sheet goes next.
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
                .provisioningStep(.place, steps: NewResourceKind.database.steps)
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
                .start, isFinished: databases.ignition.phase == .running, steps: NewResourceKind.database.steps)
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
    /// One template up close, where the service is placed, named, and created.
    case template(ServiceTemplate)
    /// The created service's domains and settings, before its first start.
    case setUp
    /// The first start, watched until the service runs.
    case start
    /// One database engine, where the database is placed, named, created, and started.
    case database(DatabaseEngine)
    /// A new database's first start, with how to connect to it.
    case databaseStart
}

/// What the sheet creates. Coolify's one-click services, or a database on its own.
enum NewResourceKind: CaseIterable, Identifiable, Hashable {
    case service
    case database

    var id: Self { self }

    var title: String {
        switch self {
        case .service: "Service"
        case .database: "Database"
        }
    }

    /// A database skips setup, since Coolify starts it as it creates it.
    var steps: [ProvisioningStep] {
        switch self {
        case .service: ProvisioningStep.allCases
        case .database: [.choose, .place, .start]
        }
    }
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

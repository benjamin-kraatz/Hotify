import CoolifyAPI
import SwiftUI

/// From template to running service in one sheet: choose, place, set up, start.
///
/// Each step is a screen pushed onto the sheet's navigation stack, so going back from a template is the system's
/// own back button and swipe. The service only exists in Coolify once the user creates it on the second step.
/// From there the screens hide their way back, and closing the sheet keeps or deletes the service on purpose.
struct ProvisioningSheet: View {
    var client: CoolifyClient?
    var instanceID: UUID?
    var catalog: TemplateCatalog
    /// Closes the sheet and opens the new service, or opens nothing.
    var onClose: (ResourceRoute?) -> Void

    @State private var model: ProvisioningModel
    @State private var path: [ProvisioningRoute] = []

    init(
        client: CoolifyClient?,
        instanceID: UUID?,
        catalog: TemplateCatalog,
        model: ProvisioningModel = ProvisioningModel(),
        onClose: @escaping (ResourceRoute?) -> Void
    ) {
        self.client = client
        self.instanceID = instanceID
        self.catalog = catalog
        self.onClose = onClose
        _model = State(initialValue: model)
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
        // Once the service exists, closing has to keep or delete it, which the setup step asks about.
        .interactiveDismissDisabled(model.stage != .choosing || model.isCreating)
        #if os(macOS)
        .frame(minWidth: 680, idealWidth: 860, minHeight: 600, idealHeight: 780)
        #endif
        .task {
            model.prepare(client, instanceID: instanceID)
            async let templates: Void = catalog.load()
            async let placement: Void = model.placement.load()
            _ = await (templates, placement)
        }
    }

    private var gallery: some View {
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
        .provisioningStep(.choose)
        .navigationTitle("New Service")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onClose(nil) }
                    .disabled(model.isCreating)
            }
        }
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
}

extension View {
    /// Puts the row of step flames under the navigation bar, saying how far along the sheet is.
    fileprivate func provisioningStep(_ step: ProvisioningStep, isFinished: Bool = false) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            ProvisioningSteps(current: step, isFinished: isFinished)
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

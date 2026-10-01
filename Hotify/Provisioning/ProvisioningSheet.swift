import CoolifyAPI
import SwiftUI

/// From template to running service in one sheet: choose, place, set up, start.
///
/// The service only exists in Coolify once the user creates it on the second step. From there the sheet cannot go
/// back, and closing it keeps or deletes the service on purpose.
struct ProvisioningSheet: View {
    var client: CoolifyClient?
    var instanceID: UUID?
    var catalog: TemplateCatalog
    /// Closes the sheet and opens the new service, or opens nothing.
    var onClose: (ResourceRoute?) -> Void

    @State private var model: ProvisioningModel
    @State private var chosen: ServiceTemplate?
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    private var step: ProvisioningStep {
        switch model.stage {
        case .choosing: chosen == nil ? .choose : .place
        case .settingUp: .setUp
        case .starting: .start
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                switch model.stage {
                case .choosing:
                    chooser
                        .transition(.move(edge: .leading).combined(with: .opacity))
                case .settingUp:
                    ServiceSetup(model: model, onClose: onClose)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                case .starting:
                    IgnitionView(
                        name: model.serviceName,
                        ignition: model.ignition,
                        addresses: addresses,
                        onOpen: { onClose(model.route) },
                        onClose: { onClose(nil) }
                    )
                    .task { await model.watch() }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                ProvisioningSteps(current: step, isFinished: model.ignition.phase == .running && step == .start)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.bar)
                    .overlay(alignment: .bottom) { Divider() }
            }
            .toolbar {
                if model.stage == .choosing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onClose(nil) }
                            .disabled(model.isCreating)
                    }
                }
            }
            #if os(iOS)
            .navigationTitle(step == .choose ? "New Service" : "")
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .tint(.ember)
        .animation(reduceMotion ? nil : .snappy, value: model.stage)
        .animation(reduceMotion ? nil : .snappy, value: chosen?.slug)
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

    @ViewBuilder
    private var chooser: some View {
        ZStack {
            if let chosen {
                TemplateLaunchPad(template: chosen, model: model, instanceRoot: model.instanceRoot) {
                    self.chosen = nil
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
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
                        chosen = template
                    }
                )
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
    }

    /// The service's public addresses, first one per container.
    private var addresses: [URL] {
        model.setup.domains.compactMap { domain in
            domain.trimmed.split(separator: ",").first.flatMap { URL(string: String($0)) }
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

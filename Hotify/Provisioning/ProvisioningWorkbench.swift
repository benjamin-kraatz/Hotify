import CoolifyAPI
import SwiftUI

/// The New Resource sheet on the Mac and iPad: choosing, placing, and naming on one screen.
///
/// Three columns. The sidebar picks a list or a source. The middle column lists templates or engines, or holds a
/// compose file, a Dockerfile, or a repository's fields. The inspector shows what is chosen, where it will run, its
/// name, and the button that creates it. One search above them finds templates, engines, and sources together.
struct ProvisioningWorkbench: View {
    var models: NewResourceModels
    var catalog: TemplateCatalog
    var instanceRoot: URL?
    var onCancel: () -> Void

    @State private var source = ProvisioningSource.list(.popular)
    /// The row chosen in the middle column's list, which the inspector opens.
    @State private var selection: CatalogEntry?
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    /// The middle column's rows, or `nil` when it holds a file or fields instead.
    private var listEntries: [CatalogEntry]? {
        if !trimmedQuery.isEmpty { return CatalogScope.search(trimmedQuery, in: catalog.shelves) }
        if case .list(let scope) = source { return scope.entries(in: catalog.shelves) }
        return nil
    }

    /// Rows the inspector can open beside the list. A compose file or an application source needs the middle column
    /// for itself, so choosing one from a search moves to its own sidebar row instead.
    private var openableEntries: [CatalogEntry] {
        (listEntries ?? []).filter { ProvisioningSource(choosing: $0) == nil }
    }

    private var openEntry: CatalogEntry? {
        switch source {
        case .compose where trimmedQuery.isEmpty: return .compose
        case .application(let application) where trimmedQuery.isEmpty: return .application(application)
        default:
            guard let selection, openableEntries.contains(selection) else { return nil }
            return selection
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .disabled(models.isCreating)
            Divider()
            HStack(spacing: 0) {
                SourceSidebar(
                    selection: Binding(
                        get: { source },
                        set: { new in
                            source = new
                            query = ""
                        }),
                    shelves: catalog.shelves
                )
                .frame(width: 220)
                .disabled(models.isCreating)
                Divider()
                middle
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .disabled(models.isCreating)
                Divider()
                inspector
                    .frame(width: 370)
                    .frame(maxHeight: .infinity)
            }
        }
        .onChange(of: openableEntries.map(\.id), initial: true) { _, _ in keepSelection() }
        .onChange(of: openEntry, initial: true) { _, entry in
            if let entry { models.choose(entry, catalog: catalog) }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: source)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 16) {
            searchField
                .frame(maxWidth: 480)
            Spacer(minLength: 12)
            ProvisioningSteps(current: .create, steps: openEntry?.steps ?? ProvisioningStep.allCases)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(searchPrompt, text: $query)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onKeyPress(.downArrow) { move(by: 1) }
                .onKeyPress(.upArrow) { move(by: -1) }
            if !query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .well(cornerRadius: 8)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.ember.opacity(isSearchFocused ? 0.5 : 0), lineWidth: 1)
        }
        .animation(.snappy(duration: 0.2), value: isSearchFocused)
        .onAppear { isSearchFocused = true }
    }

    private var searchPrompt: String {
        let templates = catalog.templates.count
        let engines = DatabaseEngine.allCases.count
        let sources = NewApplicationSource.allCases.count + 1
        return templates == 0
            ? "Search templates, databases, and sources"
            : "Search \(templates) templates, \(engines) databases, and \(sources) sources"
    }

    // MARK: Middle column

    @ViewBuilder
    private var middle: some View {
        if !trimmedQuery.isEmpty, let results = listEntries {
            CatalogList(
                title: "Results", count: results.count, entries: results, selection: picking,
                instanceRoot: instanceRoot, query: trimmedQuery)
        } else {
            switch source {
            case .list(let scope):
                CatalogList(
                    title: scope.title,
                    count: scope.count(in: catalog.shelves),
                    entries: scope.entries(in: catalog.shelves),
                    selection: picking,
                    instanceRoot: instanceRoot,
                    isTemplates: scope.isTemplates,
                    isLoading: catalog.isLoading,
                    loadError: catalog.loadError,
                    onRetry: { Task { await catalog.refresh() } }
                )
            case .compose:
                composeEditor
            case .application(let application):
                Form {
                    ApplicationSourceFields(source: application, model: models.applications)
                }
                .formStyle(.grouped)
            }
        }
    }

    private var composeEditor: some View {
        @Bindable var services = models.services
        return ComposeEditor(compose: $services.compose)
            .padding(16)
    }

    /// The list's selection as the user changes it. A compose file or an application source opens its own row, and
    /// an engine found in a search keeps the engines' row behind the results.
    private var picking: Binding<CatalogEntry?> {
        Binding(
            get: { selection },
            set: { entry in
                guard let entry else { return }
                if let own = ProvisioningSource(choosing: entry) {
                    source = own
                    query = ""
                } else {
                    if case .engine = entry { source = .list(.databases) }
                    selection = entry
                }
            })
    }

    /// Keeps the chosen row when the list still has it, and otherwise opens the first, so the inspector is never
    /// empty while there is something to show.
    private func keepSelection() {
        let entries = openableEntries
        if let selection, entries.contains(selection) { return }
        selection = entries.first
    }

    private func move(by offset: Int) -> KeyPress.Result {
        let entries = openableEntries
        guard !entries.isEmpty else { return .ignored }
        let current = selection.flatMap { entries.firstIndex(of: $0) } ?? -offset
        let next = min(max(current + offset, 0), entries.count - 1)
        selection = entries[next]
        return .handled
    }

    // MARK: Inspector

    private var inspector: some View {
        Group {
            if let entry = openEntry {
                launchPad(entry)
                    .id(entry.id)
            } else {
                emptyInspector
            }
        }
        .environment(\.isProvisioningInspector, true)
        .environment(\.provisioningCancel, ProvisioningCancel(close: onCancel))
    }

    @ViewBuilder
    private func launchPad(_ entry: CatalogEntry) -> some View {
        switch entry {
        case .template(let template):
            TemplateLaunchPad(template: template, model: models.services, instanceRoot: instanceRoot)
        case .engine(let engine):
            DatabaseLaunchPad(engine: engine, model: models.databases, instanceRoot: instanceRoot)
        case .compose:
            ComposeLaunchPad(model: models.services, instanceRoot: instanceRoot, showsEditor: false)
        case .application(let application):
            ApplicationLaunchPad(
                source: application, model: models.applications, instanceRoot: instanceRoot, showsSource: false)
        }
    }

    private var emptyInspector: some View {
        VStack(spacing: 0) {
            ContentUnavailableView {
                Label {
                    Text("Nothing chosen")
                } icon: {
                    FlameGlyph(heat: .cold, height: 40)
                }
            } description: {
                Text("Pick a template, an engine, or a source, and it opens here.")
            }
            .frame(maxHeight: .infinity)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .glassButton()
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.bar)
        }
    }
}

#Preview {
    let placement = PlacementModel(
        servers: [Server(uuid: "s1", name: "localhost", isReachable: true)],
        projects: [Project(uuid: "p1", name: "Website", environments: [Environment(uuid: "e1", name: "production")])],
        placement: Placement(serverUUID: "s1", projectUUID: "p1", environmentUUID: "e1")
    )
    ProvisioningWorkbench(
        models: NewResourceModels(
            services: ProvisioningModel(placement: placement),
            databases: DatabaseProvisioningModel(placement: placement),
            applications: ApplicationProvisioningModel(placement: placement)
        ),
        catalog: TemplateCatalog(templates: [
            ServiceTemplate(slug: "n8n", slogan: "Workflow automation for technical people.", category: "automation"),
            ServiceTemplate(slug: "ghost", slogan: "A content management system.", category: "cms"),
            ServiceTemplate(slug: "uptime-kuma", slogan: "A fancy monitoring tool.", category: "monitoring"),
        ]),
        onCancel: {}
    )
    .frame(width: 1080, height: 720)
    .tint(.ember)
}

import CoolifyAPI
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Makes a Shortcut automation, or changes one: the Shortcut to run, the instance and resource, and on the Mac the
/// event that runs it. It opens with what an automation can and can't do here, since that differs by device.
struct AutomationEditor: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @SwiftUI.Environment(InstanceStore.self) private var instances
    @SwiftUI.Environment(AutomationStore.self) private var automations
    @SwiftUI.Environment(AutomationRunner.self) private var runner: AutomationRunner?
    #if os(macOS)
    /// Missing in previews.
    @SwiftUI.Environment(MenuBarModel.self) private var menuBar: MenuBarModel?
    #endif
    @SwiftUI.Environment(\.openURL) private var openURL
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draft: ShortcutAutomation
    private let isNew: Bool
    /// The instance's resources, loaded to pick from. Previews pass their own.
    @State private var resources: [ResourceSummary]
    private let loadsResources: Bool
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testFailed = false
    /// Counts the results shown, so each new one bounces its symbol.
    @State private var testArrivals = 0
    @State private var showsInput = false
    @State private var copiedInput = false

    init(automation: ShortcutAutomation?, instanceID: UUID?, previewResources: [ResourceSummary]? = nil) {
        isNew = automation == nil
        _draft = State(
            initialValue: automation
                ?? ShortcutAutomation(
                    shortcutName: "", instanceID: instanceID ?? UUID(), trigger: AutomationTrigger.available[0]))
        _resources = State(initialValue: previewResources ?? [])
        loadsResources = previewResources == nil
    }

    private var instance: CoolifyInstance? {
        instances.instances.first { $0.id == draft.instanceID }
    }

    /// The events the chosen resource can have. Any resource can have all of them.
    private var triggers: [AutomationTrigger] {
        guard let kind = draft.resource?.route?.kind else { return AutomationTrigger.available }
        return AutomationTrigger.available.filter { $0.applies(to: kind) }
    }

    private var keepsRunning: Bool {
        #if os(macOS)
        menuBar?.enabled ?? false
        #else
        false
        #endif
    }

    private var problem: String? {
        if instance == nil { return "Choose an instance." }
        return draft.problem
    }

    private var runTitle: String {
        draft.trigger.isAutomatic ? "Test Run" : "Run Now"
    }

    private var resourceFooter: String {
        if draft.resource != nil { return "This resource only, even once it's renamed." }
        return draft.trigger.isAutomatic
            ? "Any resource on the instance that the event can happen to."
            : "The instance as a whole, with no resource named."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AutomationLimits(keepsRunning: keepsRunning)
                    #if os(macOS)
                    if let menuBar, !menuBar.enabled {
                        Toggle(
                            "Show Hotify in the menu bar",
                            isOn: Binding(get: { menuBar.enabled }, set: { menuBar.enabled = $0 }))
                    }
                    #endif
                }

                Section {
                    TextField("Shortcut", text: $draft.shortcutName, prompt: Text("Name in the Shortcuts app"))
                        .autocorrectionDisabled()
                    HStack {
                        Button("New Shortcut", systemImage: "plus") { openURL(ShortcutLink.create) }
                        Spacer()
                        Button("Open in Shortcuts", systemImage: "arrow.up.forward.app") {
                            openURL(ShortcutLink.open(draft.shortcutName) ?? ShortcutLink.app)
                        }
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text("Shortcut")
                } footer: {
                    Text("Type the name exactly as Shortcuts shows it. Hotify can't list your Shortcuts.")
                }

                Section {
                    Picker("Instance", selection: $draft.instanceID) {
                        if instance == nil {
                            Text("Choose…").tag(draft.instanceID)
                        }
                        ForEach(instances.instances) { instance in
                            Text(instance.name).tag(instance.id)
                        }
                    }
                    Picker("Resource", selection: resourceSelection) {
                        Text("Any resource").tag(Optional<ResourceRoute>.none)
                        if let saved = draft.resource, let route = saved.route,
                            !resources.contains(where: { $0.route == route })
                        {
                            Label(saved.name, systemImage: route.kind.systemImage).tag(Optional(route))
                        }
                        ForEach(resources) { resource in
                            Label(resource.name, systemImage: resource.kind.systemImage).tag(Optional(resource.route))
                        }
                    }
                    .disabled(isLoading)
                    if isLoading {
                        HStack {
                            Text("Loading resources…")
                                .foregroundStyle(.secondary)
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    if let loadError {
                        Label(loadError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.glow)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("Resource")
                } footer: {
                    Text(resourceFooter)
                }

                Section {
                    #if os(macOS)
                    Picker("Runs", selection: $draft.trigger) {
                        ForEach(triggers) { trigger in
                            Label(trigger.title, systemImage: trigger.systemImage).tag(trigger)
                        }
                    }
                    #else
                    LabeledContent("Runs") {
                        Label(AutomationTrigger.manual.title, systemImage: AutomationTrigger.manual.systemImage)
                    }
                    #endif
                } header: {
                    Text("When")
                } footer: {
                    Text(draft.trigger.detail)
                }

                Section {
                    DisclosureGroup(isExpanded: $showsInput) {
                        sampleInput
                    } label: {
                        Text("What the Shortcut gets")
                    }
                    Button {
                        Task { await test() }
                    } label: {
                        HStack {
                            Label(runTitle, systemImage: "play")
                            Spacer()
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(problem != nil || isTesting || runner == nil)
                    if let testResult {
                        Label {
                            Text(testResult)
                                .fixedSize(horizontal: false, vertical: true)
                                .contentTransition(.opacity)
                        } icon: {
                            Image(
                                systemName: testFailed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                            )
                            .foregroundStyle(testFailed ? Color.glow : Color.ember)
                            .symbolEffect(.bounce, value: testArrivals)
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                } footer: {
                    Text(
                        draft.trigger.isAutomatic
                            ? "A test run sends the same fields, with \"test\": true, so the Shortcut can tell it apart."
                            : "Run Now sends these fields, with \"test\": true, since it ran from here.")
                }

                if let problem, !draft.trimmedShortcutName.isEmpty || !isNew {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.glow)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "New Automation" : "Edit Automation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") {
                        automations.save(draft)
                        dismiss()
                    }
                    .disabled(problem != nil)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .task(id: draft.instanceID) { await loadResources() }
            .onChange(of: draft) { _, _ in
                testResult = nil
                copiedInput = false
            }
            .onChange(of: triggers) { _, triggers in
                if !triggers.contains(draft.trigger), let first = triggers.first { draft.trigger = first }
            }
            .animation(reduceMotion ? nil : .snappy, value: testResult)
            .animation(reduceMotion ? nil : .snappy, value: problem)
            .animation(reduceMotion ? nil : .snappy, value: isLoading)
            .animation(reduceMotion ? nil : .snappy, value: loadError)
            .animation(reduceMotion ? nil : .snappy, value: showsInput)
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 500, minHeight: 640, idealHeight: 760)
        #endif
    }

    /// The JSON a test would send, to read or to paste into the Shortcut while building it.
    private var sampleInput: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(samplePayload)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .well(cornerRadius: 8)
                .accessibilityLabel("Sample input")
                .accessibilityValue(samplePayload)
            Button(copiedInput ? "Copied" : "Copy", systemImage: copiedInput ? "checkmark" : "doc.on.doc") {
                copyInput()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .contentTransition(.symbolEffect(.replace))
            .help("Copy the sample input")
        }
        .padding(.vertical, 4)
        .animation(reduceMotion ? nil : .snappy, value: copiedInput)
    }

    private var resourceSelection: Binding<ResourceRoute?> {
        Binding(
            get: { draft.resource?.route },
            set: { route in
                guard let route else {
                    draft.resource = nil
                    return
                }
                let name = resources.first { $0.route == route }?.name ?? draft.resource?.name ?? route.uuid
                draft.resource = ShortcutAutomation.Resource(route: route, name: name)
            }
        )
    }

    private var samplePayload: String {
        guard let instance else { return "{}" }
        let payload = ShortcutPayload(testing: draft, instanceName: instance.name, instanceURL: instance.baseURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(payload)).map { String(decoding: $0, as: UTF8.self) } ?? payload.json
    }

    private func copyInput() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(samplePayload, forType: .string)
        #else
        UIPasteboard.general.string = samplePayload
        #endif
        copiedInput = true
    }

    private func test() async {
        guard let instance, let runner else { return }
        isTesting = true
        defer { isTesting = false }
        let failure = await runner.runNow(draft, instance: instance)
        testFailed = failure != nil
        testResult = failure ?? "Handed to Shortcuts. Check there that it did what you wanted."
        if !reduceMotion { testArrivals += 1 }
    }

    private func loadResources() async {
        guard loadsResources else { return }
        resources = []
        loadError = nil
        guard let instance, let client = instances.client(for: instance) else {
            if instance != nil { loadError = "No API token for this instance on this device." }
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            async let apps = client.applications()
            async let databases = client.databases()
            async let services = client.services()
            let loaded = try await (apps, databases, services)
            try Task.checkCancellation()
            resources =
                (loaded.0.map { ResourceSummary(application: $0) }
                + loaded.1.map { ResourceSummary(database: $0) } + loaded.2.map { ResourceSummary(service: $0) })
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch is CancellationError {
            return
        } catch {
            loadError = (error as? CoolifyError)?.summary ?? error.localizedDescription
        }
    }
}

#Preview("New") {
    let instance = CoolifyInstance(name: "Home lab", baseURL: URL(string: "https://coolify.example.com")!)
    AutomationEditor(
        automation: nil, instanceID: instance.id,
        previewResources: [
            ResourceSummary(route: .application("web"), name: "marketing-site", status: "running:healthy"),
            ResourceSummary(route: .database("pg"), name: "postgres", status: "running:healthy"),
        ]
    )
    .environment(InstanceStore(instances: [instance]))
    .environment(AutomationStore(defaults: nil))
}

#Preview("Edit") {
    let instance = CoolifyInstance(name: "Home lab", baseURL: URL(string: "https://coolify.example.com")!)
    AutomationEditor(
        automation: ShortcutAutomation(
            shortcutName: "Post to Team Chat", instanceID: instance.id,
            resource: ShortcutAutomation.Resource(route: .application("web"), name: "marketing-site"),
            trigger: AutomationTrigger.available[0]),
        instanceID: instance.id,
        previewResources: [
            ResourceSummary(route: .application("web"), name: "marketing-site", status: "running:healthy")
        ]
    )
    .environment(InstanceStore(instances: [instance]))
    .environment(AutomationStore(defaults: nil))
}

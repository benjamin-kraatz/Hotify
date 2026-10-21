import CoolifyAPI
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Makes a Shortcut automation, or changes one. It reads as one sentence at the top, filled in by three steps under
/// it: when it runs, where, and which Shortcut. A test run and what the Shortcut receives follow, and what an
/// automation can and can't do on this device waits at the end, since that differs by device.
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
    @State private var showsInput = false
    @State private var showsLimits = false
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

    /// The resources the chosen event can happen to. Only applications deploy, and only databases back up.
    private var eligibleResources: [ResourceSummary] {
        resources.filter { draft.trigger.applies(to: $0.kind) }
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

    private var whereFooter: String {
        if draft.resource != nil { return "This resource only, even once it's renamed." }
        return draft.trigger.isAutomatic
            ? "\(AutomationSentence.anyResource(for: draft.trigger).capitalized) on the instance that the event can happen to."
            : "The instance as a whole, with no resource named."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        AutomationSentence(automation: draft, instanceName: instance?.name)
                        if let problem, !draft.trimmedShortcutName.isEmpty || !isNew {
                            Label(problem, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(.glow)
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity)
                        }
                    }

                    step(1, "When", caption: whenCaption) {
                        AutomationTriggerPicker(selection: $draft.trigger)
                    }

                    step(2, "Where", caption: whereFooter) {
                        wherePicker
                    }

                    step(3, "Run", caption: "Type the name exactly as Shortcuts shows it. Hotify can't list them.") {
                        shortcutField
                    }

                    tryIt

                    #if os(macOS)
                    if let menuBar, !menuBar.enabled, draft.trigger.isAutomatic {
                        keepRunningNotice(menuBar)
                    }
                    #endif

                    DisclosureGroup(isExpanded: $showsLimits) {
                        AutomationLimits(keepsRunning: keepsRunning)
                            .padding(.top, 10)
                    } label: {
                        Label("How this runs on this \(AutomationLimits.deviceName)", systemImage: "info.circle")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 2)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
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
            .onChange(of: draft.trigger) { _, trigger in
                // The resource that was chosen can't have the new event, so the automation widens to any that can.
                if let kind = draft.resource?.route?.kind, !trigger.applies(to: kind) { draft.resource = nil }
            }
            .animation(reduceMotion ? nil : .snappy, value: testResult)
            .animation(reduceMotion ? nil : .snappy, value: problem)
            .animation(reduceMotion ? nil : .snappy, value: isLoading)
            .animation(reduceMotion ? nil : .snappy, value: loadError)
            .animation(reduceMotion ? nil : .snappy, value: showsInput)
            .animation(reduceMotion ? nil : .snappy, value: showsLimits)
            .animation(reduceMotion ? nil : .snappy, value: keepsRunning)
        }
        #if os(macOS)
        .frame(minWidth: 540, idealWidth: 580, minHeight: 640, idealHeight: 780)
        #endif
    }

    private var whenCaption: String {
        #if os(macOS)
        "Hotify sees these while it checks the instance, every 30 seconds."
        #else
        "\(AutomationLimits.deviceName) can't run a Shortcut on its own. The Mac app can."
        #endif
    }

    /// A numbered part of the editor: its number and title above `content`, and a caption under it.
    private func step<Content: View>(
        _ number: Int, _ title: String, caption: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.ember)
                    .frame(width: 22, height: 22)
                    .background(.ember.opacity(0.14), in: .circle)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Step \(number), \(title)")
            .accessibilityAddTraits(.isHeader)
            content()
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
                .contentTransition(.opacity)
        }
    }

    private var wherePicker: some View {
        VStack(spacing: 0) {
            pickerRow("Instance") {
                Picker("Instance", selection: $draft.instanceID) {
                    if instance == nil {
                        Text("Choose…").tag(draft.instanceID)
                    }
                    ForEach(instances.instances) { instance in
                        Text(instance.name).tag(instance.id)
                    }
                }
            }
            Divider()
                .padding(.leading, 14)
            pickerRow("Resource") {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Picker("Resource", selection: resourceSelection) {
                    Text(AutomationSentence.anyResource(for: draft.trigger).capitalized)
                        .tag(Optional<ResourceRoute>.none)
                    if let saved = draft.resource, let route = saved.route,
                        !resources.contains(where: { $0.route == route })
                    {
                        Label(saved.name, systemImage: route.kind.systemImage).tag(Optional(route))
                    }
                    ForEach(eligibleResources) { resource in
                        Label(resource.name, systemImage: resource.kind.systemImage).tag(Optional(resource.route))
                    }
                }
                .disabled(isLoading || instance == nil)
            }
            if let loadError {
                NoticeBanner(message: loadError)
                    .padding(14)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .well()
    }

    private func pickerRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var shortcutField: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.2.layers.3d")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(draft.trimmedShortcutName.isEmpty ? Color.secondary : Color.ember)
                    .frame(width: 30, height: 30)
                    .background(
                        (draft.trimmedShortcutName.isEmpty ? Color.secondary : Color.ember).opacity(0.12),
                        in: .rect(cornerRadius: 9, style: .continuous)
                    )
                    .accessibilityHidden(true)
                TextField("Shortcut", text: $draft.shortcutName, prompt: Text("Name in the Shortcuts app"))
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            Divider()
                .padding(.leading, 14)
            HStack {
                Button("New Shortcut", systemImage: "plus") { openURL(ShortcutLink.create) }
                Spacer()
                Button("Open in Shortcuts", systemImage: "arrow.up.forward.app") {
                    openURL(ShortcutLink.open(draft.shortcutName) ?? ShortcutLink.app)
                }
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .well()
        .animation(reduceMotion ? nil : .snappy, value: draft.trimmedShortcutName.isEmpty)
    }

    /// A test run, its result, and the JSON the Shortcut gets.
    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Try it")
                        .font(.headline)
                    Text(
                        draft.trigger.isAutomatic
                            ? "Sends the same fields, with \"test\": true, so the Shortcut can tell it apart."
                            : "Sends these fields, with \"test\": true, since it ran from here."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button {
                    Task { await test() }
                } label: {
                    HStack(spacing: 6) {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text(runTitle)
                    }
                }
                .glassButton()
                .disabled(problem != nil || isTesting || runner == nil)
            }
            if let testResult {
                NoticeBanner(message: testResult, tone: testFailed ? .problem : .done)
            }
            DisclosureGroup(isExpanded: $showsInput) {
                sampleInput
            } label: {
                Text("What the Shortcut gets")
                    .font(.subheadline.weight(.medium))
            }
        }
        .padding(14)
        .well()
    }

    #if os(macOS)
    /// Closing the last window would quit Hotify and stop the automation. The switch keeps it in the menu bar.
    private func keepRunningNotice(_ menuBar: MenuBarModel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.glow)
                .frame(width: 30, height: 30)
                .background(.glow.opacity(0.14), in: .rect(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Keep Hotify in the menu bar")
                    .font(.subheadline.weight(.semibold))
                Text("Closing Hotify's last window quits it, which pauses this automation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle(
                "Show Hotify in the menu bar",
                isOn: Binding(get: { menuBar.enabled }, set: { menuBar.enabled = $0 })
            )
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(14)
        .background(.glow.opacity(0.1), in: .rect(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.glow.opacity(0.18), lineWidth: 1)
        }
        .transition(.opacity)
    }
    #endif

    /// The JSON a test would send, to read or to paste into the Shortcut while building it.
    private var sampleInput: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(samplePayload)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.background.opacity(0.6), in: .rect(cornerRadius: 8, style: .continuous))
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
        .padding(.top, 8)
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

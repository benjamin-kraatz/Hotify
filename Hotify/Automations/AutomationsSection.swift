import CoolifyAPI
import SwiftUI

/// The Shortcut Automations part of Settings: the automations of this device, a switch and Run for each, and the way
/// to make a new one. They run here, which the footer says, unlike a resource's deployment commands, which Coolify
/// runs on its server.
struct AutomationsSection: View {
    @SwiftUI.Environment(AutomationStore.self) private var automations
    @SwiftUI.Environment(AutomationRunner.self) private var runner: AutomationRunner?
    @SwiftUI.Environment(InstanceStore.self) private var instances
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editing: EditorTarget?
    @State private var deleting: ShortcutAutomation?
    @State private var running: UUID?

    var body: some View {
        Section {
            if instances.instances.isEmpty {
                Text("Add an instance to run a Shortcut for it.")
                    .foregroundStyle(.secondary)
            } else if automations.automations.isEmpty {
                emptyState
            }
            ForEach(automations.automations) { automation in
                row(automation)
            }
            if !automations.automations.isEmpty {
                Button("New Automation…", systemImage: "plus") {
                    editing = EditorTarget(automation: nil)
                }
            }
        } footer: {
            Text(footer)
        }
        .sheet(item: $editing) { target in
            AutomationEditor(
                automation: target.automation, instanceID: target.automation?.instanceID ?? defaultInstanceID)
        }
        .confirmationDialog(
            deleting.map { "Delete the automation for \($0.trimmedShortcutName)?" } ?? "",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { automation in
            Button("Delete", role: .destructive) {
                automations.remove(automation.id)
            }
        } message: { _ in
            Text("The Shortcut itself stays in the Shortcuts app.")
        }
        .animation(reduceMotion ? nil : .snappy, value: automations.automations)
        .animation(reduceMotion ? nil : .snappy, value: automations.lastRuns)
    }

    private var defaultInstanceID: UUID? {
        instances.selected?.id ?? instances.instances.first?.id
    }

    /// What the section shows before the first automation: what one does here, and the one way to make it.
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.2.layers.3d")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.ember)
                .frame(width: 56, height: 56)
                .background(.ember.opacity(0.12), in: .rect(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("No automations yet")
                    .font(.headline)
                Text(emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("New Automation…", systemImage: "plus") {
                editing = EditorTarget(automation: nil)
            }
            .glassButton(prominent: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var emptyMessage: String {
        #if os(macOS)
        "One runs a Shortcut of yours when a deploy ends, a resource stops, or a backup fails."
        #else
        "One runs a Shortcut of yours for a resource when you tap Run."
        #endif
    }

    private var footer: String {
        #if os(macOS)
        "These run on this Mac while Hotify runs, not on the Coolify server. They aren't synced to other devices."
        #else
        "These run on this \(AutomationLimits.deviceName) when you tap Run, not on the Coolify server. They aren't synced to other devices."
        #endif
    }

    private func row(_ automation: ShortcutAutomation) -> some View {
        let instance = instances.instances.first { $0.id == automation.instanceID }
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: automation.trigger.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(automation.isEnabled ? Color.ember : Color.secondary)
                .frame(width: 32, height: 32)
                .background(
                    (automation.isEnabled ? Color.ember : Color.secondary).opacity(0.12),
                    in: .rect(cornerRadius: 9, style: .continuous)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(automation.trimmedShortcutName)
                    .fontWeight(.semibold)
                Text(scopeLine(automation, instance: instance))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let line = lastRunLine(automation) {
                    Text(line.text)
                        .font(.caption)
                        .foregroundStyle(line.isProblem ? Color.glow : Color.secondary)
                        .lineLimit(2)
                        .contentTransition(.opacity)
                }
            }
            Spacer(minLength: 8)
            if running == automation.id {
                ProgressView()
                    .controlSize(.small)
            }
            #if os(macOS)
            if automation.trigger.isAutomatic {
                Toggle(
                    "On",
                    isOn: Binding(
                        get: { automation.isEnabled },
                        set: { automations.setEnabled($0, for: automation.id) })
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            #endif
            Menu {
                Button(automation.trigger.isAutomatic ? "Test Run" : "Run", systemImage: "play") {
                    Task { await run(automation) }
                }
                .disabled(instance == nil || runner == nil || running != nil)
                Button("Edit", systemImage: "pencil") {
                    editing = EditorTarget(automation: automation)
                }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    deleting = automation
                }
            } label: {
                Label("Actions for \(automation.trimmedShortcutName)", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .accessibilityElement(children: .contain)
    }

    private func scopeLine(_ automation: ShortcutAutomation, instance: CoolifyInstance?) -> String {
        let place = [automation.resource?.name ?? "Any resource", instance?.name ?? "Removed instance"]
            .joined(separator: " · ")
        return "\(automation.trigger.title) · \(place)"
    }

    private func lastRunLine(_ automation: ShortcutAutomation) -> (text: String, isProblem: Bool)? {
        guard let last = automations.lastRuns[automation.id] else { return nil }
        let when = last.date.formatted(.relative(presentation: .named))
        let subject = last.resourceName.map { " for \($0)" } ?? ""
        if last.wasSkipped {
            return ("Held back \(when)\(subject): it ran 3 times in a minute.", true)
        }
        if let failure = last.failure {
            return ("\(failure) (\(when))", true)
        }
        return ("\(last.reason) \(when)\(subject)", false)
    }

    private func run(_ automation: ShortcutAutomation) async {
        guard let runner, let instance = instances.instances.first(where: { $0.id == automation.instanceID }) else {
            return
        }
        running = automation.id
        defer { running = nil }
        await runner.runNow(automation, instance: instance)
    }
}

private struct EditorTarget: Identifiable {
    var automation: ShortcutAutomation?
    var id: String { automation?.id.uuidString ?? "new" }
}

#Preview {
    let instance = CoolifyInstance(name: "Home lab", baseURL: URL(string: "https://coolify.example.com")!)
    Form {
        AutomationsSection()
    }
    .formStyle(.grouped)
    .environment(InstanceStore(instances: [instance]))
    .environment(
        AutomationStore(
            defaults: nil,
            automations: [
                ShortcutAutomation(
                    shortcutName: "Post to Team Chat", instanceID: instance.id,
                    resource: ShortcutAutomation.Resource(route: .application("web"), name: "marketing-site"),
                    trigger: AutomationTrigger.available[0]),
                ShortcutAutomation(
                    shortcutName: "Page Me", instanceID: instance.id, trigger: .manual, isEnabled: true),
            ])
    )
    .frame(width: 500, height: 320)
}

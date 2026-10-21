import CoolifyAPI
import Foundation
import os

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Opens Shortcuts for the automations a change calls for, and for a run by hand. Hotify hands the Shortcut its
/// input through the Shortcuts URL and learns nothing back but whether Shortcuts took the link. What the Shortcut
/// then does is up to it and to the permissions it has.
@Observable
final class AutomationRunner {
    let store: AutomationStore
    @ObservationIgnored private var dispatcher = AutomationDispatcher()

    private static let log = Logger(subsystem: "com.sebastiankraatz.Hotify", category: "automations")

    init(store: AutomationStore) {
        self.store = store
    }

    /// Runs what the changes from one look at `instance` call for. The instance watch only reports changes it saw
    /// happen, so a first look, a restart of Hotify, or an edit to an automation runs nothing.
    func handle(_ notices: [Notice], instance: CoolifyInstance) async {
        guard !notices.isEmpty else { return }
        let (runs, skipped) = dispatcher.runs(for: notices, automations: store.automations(for: instance.id))
        for skip in skipped {
            store.record(
                AutomationStore.LastRun(
                    date: .now, reason: skip.automation.trigger.title,
                    resourceName: skip.notice.route == nil
                        ? nil : skip.notice.title, wasSkipped: true),
                for: skip.automation.id)
        }
        for run in runs {
            let payload = ShortcutPayload(
                notice: run.notice, trigger: run.automation.trigger, instanceName: instance.name,
                instanceURL: instance.baseURL)
            let failure = await Self.open(
                run.automation.shortcutName, payload: payload, bringsForward: false)
            store.record(
                AutomationStore.LastRun(
                    date: .now, reason: run.automation.trigger.title,
                    resourceName: payload.resource?.name, failure: failure),
                for: run.automation.id)
        }
    }

    /// Runs the automation's Shortcut now, marked as a test. Returns why it didn't open, or `nil`.
    @discardableResult
    func runNow(_ automation: ShortcutAutomation, instance: CoolifyInstance) async -> String? {
        let payload = ShortcutPayload(testing: automation, instanceName: instance.name, instanceURL: instance.baseURL)
        let failure = await Self.open(automation.shortcutName, payload: payload, bringsForward: true)
        store.record(
            AutomationStore.LastRun(
                date: .now, reason: automation.trigger.isAutomatic ? "Test run" : "Run",
                resourceName: automation.resource?.name, failure: failure),
            for: automation.id)
        return failure
    }

    /// Hands the payload to Shortcuts. Logged by event only, never with the Shortcut's name or input.
    private static func open(_ name: String, payload: ShortcutPayload, bringsForward: Bool) async -> String? {
        guard let url = ShortcutLink.run(name, text: payload.json) else { return "The automation has no Shortcut." }
        let failure = await open(url, bringsForward: bringsForward)
        if let failure {
            log.error("Shortcut not opened (\(payload.event, privacy: .public)): \(failure, privacy: .public)")
        } else {
            log.info("Shortcut opened (\(payload.event, privacy: .public))")
        }
        return failure
    }

    /// Opens a Shortcuts URL. On the Mac an automatic run asks Shortcuts not to come forward, though it still may to
    /// ask for a permission. iPhone only opens URLs while Hotify is on screen, and switches to Shortcuts to run it.
    static func open(_ url: URL, bringsForward: Bool = true) async -> String? {
        #if os(macOS)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = bringsForward
        do {
            _ = try await NSWorkspace.shared.open(url, configuration: configuration)
            return nil
        } catch {
            return "Shortcuts didn't open: \(error.localizedDescription)"
        }
        #else
        guard UIApplication.shared.applicationState == .active else {
            return "iPhone only opens Shortcuts while Hotify is on screen."
        }
        return await UIApplication.shared.open(url) ? nil : "Shortcuts didn't open."
        #endif
    }
}

import SwiftUI

/// The automation as one sentence, such as "When a deployment fails for marketing-site on Home lab, run Post to
/// Team Chat." It heads the editor and reads back every choice as it's made. A choice not made yet shows as a
/// placeholder in the sentence's own words.
struct AutomationSentence: View {
    var automation: ShortcutAutomation
    /// The instance's name, or `nil` while none is chosen.
    var instanceName: String?

    var body: some View {
        sentence
            .font(.title3)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ember.opacity(0.08))
                    .overlay {
                        LinearGradient(
                            colors: [.ember.opacity(0.1), .clear], startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        .clipShape(.rect(cornerRadius: 16, style: .continuous))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.ember.opacity(0.18), lineWidth: 1)
            }
            .contentTransition(.opacity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(plain)
    }

    private var sentence: Text {
        let shortcut = automation.trimmedShortcutName
        let run = shortcut.isEmpty ? placeholder("a Shortcut") : filled(shortcut)
        let place = instanceName.map(filled) ?? placeholder("an instance")
        switch automation.trigger {
        case .deploymentSucceeded:
            return Text("When a deployment succeeds for \(scope) on \(place), run \(run).")
        case .deploymentFailed:
            return Text("When a deployment fails for \(scope) on \(place), run \(run).")
        case .backupFailed:
            return Text("When a backup fails or runs late for \(scope) on \(place), run \(run).")
        case .resourceDown:
            return Text("When \(scope) on \(place) stops or turns unhealthy, run \(run).")
        case .manual:
            return Text("Run \(run) for \(scope) on \(place), only when you tap Run.")
        }
    }

    /// The resource, or every resource the trigger can happen to.
    private var scope: Text {
        if let resource = automation.resource {
            return filled(resource.name)
        }
        return Text(Self.anyResource(for: automation.trigger))
    }

    /// What "any resource" means for a trigger. Only applications deploy, and only databases back up.
    static func anyResource(for trigger: AutomationTrigger) -> String {
        switch trigger {
        case .deploymentSucceeded, .deploymentFailed: "any application"
        case .backupFailed: "any database"
        case .resourceDown, .manual: "any resource"
        }
    }

    private func filled(_ name: String) -> Text {
        Text(name).fontWeight(.semibold)
    }

    private func placeholder(_ words: String) -> Text {
        Text(words).foregroundStyle(.secondary)
    }

    /// The sentence without styling, for VoiceOver.
    private var plain: String {
        let shortcut = automation.trimmedShortcutName.isEmpty ? "a Shortcut" : automation.trimmedShortcutName
        let place = instanceName ?? "an instance"
        let scope = automation.resource?.name ?? Self.anyResource(for: automation.trigger)
        switch automation.trigger {
        case .deploymentSucceeded: return "When a deployment succeeds for \(scope) on \(place), run \(shortcut)."
        case .deploymentFailed: return "When a deployment fails for \(scope) on \(place), run \(shortcut)."
        case .backupFailed: return "When a backup fails or runs late for \(scope) on \(place), run \(shortcut)."
        case .resourceDown: return "When \(scope) on \(place) stops or turns unhealthy, run \(shortcut)."
        case .manual: return "Run \(shortcut) for \(scope) on \(place), only when you tap Run."
        }
    }
}

#Preview {
    let instance = UUID()
    VStack(spacing: 16) {
        AutomationSentence(
            automation: ShortcutAutomation(shortcutName: "", instanceID: instance, trigger: .deploymentFailed),
            instanceName: nil
        )
        AutomationSentence(
            automation: ShortcutAutomation(
                shortcutName: "Post to Team Chat", instanceID: instance,
                resource: ShortcutAutomation.Resource(route: .application("web"), name: "marketing-site"),
                trigger: .deploymentSucceeded),
            instanceName: "Home lab"
        )
        AutomationSentence(
            automation: ShortcutAutomation(shortcutName: "Page Me", instanceID: instance, trigger: .manual),
            instanceName: "Home lab"
        )
    }
    .padding()
    .frame(width: 520)
}

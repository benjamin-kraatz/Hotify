import AppIntents
import SwiftUI
import WidgetKit

/// What a resource button does.
enum ControlAction: String, AppEnum {
    case restart
    case redeploy

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Action")
    static let caseDisplayRepresentations: [ControlAction: DisplayRepresentation] = [
        .restart: DisplayRepresentation(title: "Restart", subtitle: "Restart the containers. Nothing is rebuilt."),
        .redeploy: DisplayRepresentation(
            title: "Redeploy", subtitle: "Pull the latest commit and rebuild. Applications only."),
    ]

    /// Only applications deploy. Anything else restarts.
    func resourceAction(for route: ResourceRoute) -> ResourceAction {
        self == .redeploy && route.kind == .application ? .deploy : .restart
    }
}

/// Which resource a button runs on, and what it does.
struct ResourceButtonIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Resource Button"

    @Parameter(title: "Resource")
    var resource: ResourceEntity?

    @Parameter(title: "Action", default: .restart)
    var action: ControlAction
}

/// Runs a button's action.
struct RunControlActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Restart or Redeploy Resource"
    static let isDiscoverable = false

    @Parameter(title: "Resource")
    var pinID: String

    @Parameter(title: "Action")
    var action: ControlAction

    init() {}

    init(pinID: String, action: ControlAction) {
        self.pinID = pinID
        self.action = action
    }

    func perform() async throws -> some IntentResult {
        guard let pin = ResourcePin(id: pinID) else { return .result() }
        try await ActionRunner.run(action.resourceAction(for: pin.route), on: pin)
        return .result()
    }
}

/// A Control Center button that restarts or redeploys one resource. On iPhone it also fits the Action button.
struct ResourceButtonControl: ControlWidget {
    static let kind = "com.sebastiankraatz.Hotify.button"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, intent: ResourceButtonIntent.self) { configuration in
            let name = configuration.resource?.name ?? "Resource"
            let action = configuration.resource?.pin.map { configuration.action.resourceAction(for: $0.route) }
            ControlWidgetButton(
                action: RunControlActionIntent(pinID: configuration.resource?.id ?? "", action: configuration.action)
            ) {
                Label(
                    "\(action?.title ?? "Restart") \(name)",
                    systemImage: action?.systemImage ?? ResourceAction.restart.systemImage
                )
            }
            .tint(.ember)
        }
        .displayName("Restart or Redeploy")
        .description("Restart or redeploy one resource.")
        .promptsForUserConfiguration()
    }
}

import AppIntents
import WidgetKit

/// The action behind a widget's buttons. Stop asks twice: the first tap arms it, the second within a few seconds
/// sends it, so a stray tap cannot take a site down.
struct ResourceActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Resource Action"
    static let isDiscoverable = false

    @Parameter(title: "Resource")
    var pinID: String

    @Parameter(title: "Action")
    var action: String

    init() {}

    init(pin: ResourcePin, action: ResourceAction) {
        pinID = pin.id
        self.action = action.rawValue
    }

    func perform() async throws -> some IntentResult {
        guard let pin = ResourcePin(id: pinID), let action = ResourceAction(rawValue: action) else {
            return .result()
        }
        if action == .stop {
            let confirmed = WidgetLedger.update { $0.confirmStop(pin.id) }
            guard confirmed else { return .result() }
        } else {
            WidgetLedger.update { $0.armedStop = nil }
        }
        // A refused action shows on the tile, which the widget redraws after this returns.
        try? await ActionRunner.run(action, on: pin)
        return .result()
    }
}

import AppIntents
import WidgetKit

/// Which resource a Start or Stop control runs on.
struct ResourceControlIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Resource"

    @Parameter(title: "Resource")
    var resource: ResourceEntity?
}

/// Starts a resource when the control turns on and stops it when it turns off.
struct SetPowerIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Start or Stop Resource"
    static let isDiscoverable = false

    @Parameter(title: "Resource")
    var pinID: String

    @Parameter(title: "Running")
    var value: Bool

    init() {}

    init(pinID: String) {
        self.pinID = pinID
    }

    func perform() async throws -> some IntentResult {
        guard let pin = ResourcePin(id: pinID) else { return .result() }
        try await ActionRunner.run(value ? .start : .stop, on: pin)
        return .result()
    }
}

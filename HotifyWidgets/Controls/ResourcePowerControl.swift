import AppIntents
import SwiftUI
import WidgetKit

/// A Control Center toggle that starts and stops one resource. On iPhone it also fits the Action button.
///
/// Unlike the widget's Stop, this one does not ask twice. Opening Control Center and picking the toggle is already
/// the deliberate step.
struct ResourcePowerControl: ControlWidget {
    static let kind = "com.sebastiankraatz.Hotify.power"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, provider: PowerValueProvider()) { value in
            ControlWidgetToggle(isOn: value.isOn, action: SetPowerIntent(pinID: value.pinID)) {
                Label(value.name, systemImage: "flame")
            } valueLabel: { isOn in
                Label(isOn ? "Running" : "Stopped", systemImage: isOn ? "flame.fill" : "flame")
            }
            .tint(.ember)
        }
        .displayName("Start or Stop")
        .description("Start or stop one resource.")
        .promptsForUserConfiguration()
    }
}

/// What the toggle shows: the resource's name, and whether it runs or is on its way up.
struct PowerValue {
    var pinID: String
    var name: String
    var isOn: Bool
}

/// Reads the resource when Control Center opens. An action in flight counts as done, so the toggle does not flip
/// back while Coolify catches up.
struct PowerValueProvider: AppIntentControlValueProvider {
    func previewValue(configuration: ResourceControlIntent) -> PowerValue {
        PowerValue(
            pinID: configuration.resource?.id ?? "", name: configuration.resource?.name ?? "Resource", isOn: true)
    }

    func currentValue(configuration: ResourceControlIntent) async throws -> PowerValue {
        guard let entity = configuration.resource, let pin = entity.pin else {
            return PowerValue(pinID: "", name: "Resource", isOn: false)
        }
        let fresh = await ResourceProbe.read([pin], previous: WidgetLedger.load().readings)
        let ledger = WidgetLedger.update { ledger in
            ledger.absorb(fresh)
            return ledger
        }
        let name = ledger.readings[pin.id].flatMap { $0.name.isEmpty ? nil : $0.name } ?? entity.name
        let isOn: Bool
        switch ledger.transitions[pin.id]?.action {
        case .stop:
            isOn = false
        case .start, .deploy, .restart:
            isOn = true
        case .cancelDeployment, nil:
            let tile = PinTile(pin: pin, fallbackName: name, ledger: ledger, at: .now)
            isOn = tile.heat != .cold && tile.heat != .unknown
        }
        return PowerValue(pinID: pin.id, name: name, isOn: isOn)
    }
}

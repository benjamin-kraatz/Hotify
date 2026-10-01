import CoolifyAPI
import Foundation

/// Sends an action from a widget or control, then keeps the resource in its in-between state until a read shows
/// the result.
enum ActionRunner {
    static func run(_ action: ResourceAction, on pin: ResourcePin) async throws {
        guard case .success((_, let client)) = InstanceAccess.client(for: pin.instanceID) else {
            WidgetLedger.update { $0.failures[pin.id] = ActionFailure(action: action, at: .now) }
            return
        }
        let deploymentID = WidgetLedger.load().readings[pin.id]?.activeDeploymentID
        do {
            try await client.run(action, on: pin.route, deploymentID: deploymentID)
        } catch {
            WidgetLedger.update { $0.failures[pin.id] = ActionFailure(action: action, at: .now) }
            throw error
        }
        WidgetLedger.update { ledger in
            var transition = ResourceTransition(action: action)
            transition.isSending = false
            ledger.transitions[pin.id] = transition
            ledger.failures[pin.id] = nil
        }
    }
}

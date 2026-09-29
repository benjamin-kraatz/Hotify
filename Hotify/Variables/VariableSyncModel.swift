import CoolifyAPI
import Foundation

/// Holds a reviewed comparison in memory and applies it only after an explicit user action.
@Observable
final class VariableSyncModel {
    var plan: VariableSyncPlan?
    var selected: Set<String> = []
    var matchDestination = false
    var reviewing = false
    var busy = false
    var message: String?
    var changedDestination: VariableSyncEndpoint?
    var changedPreview = false

    var writes: [VariableSyncChange] {
        guard let plan else { return [] }
        return plan.changes.filter {
            switch $0.kind {
            case .create, .update: selected.contains($0.key)
            case .destinationOnly: matchDestination
            default: false
            }
        }
    }

    func reset() {
        guard !busy else { return }
        plan = nil
        selected = []
        matchDestination = false
        reviewing = false
        message = nil
    }

    func compare(
        source: VariableSyncEndpoint, destination: VariableSyncEndpoint, sourceClient: CoolifyClient,
        destinationClient: CoolifyClient, sourcePreview: Bool, destinationPreview: Bool
    ) async {
        reset()
        guard
            !(sourceClient.apiBaseURL == destinationClient.apiBaseURL
                && source.resource.route == destination.resource.route && sourcePreview == destinationPreview)
        else {
            message = "Choose two different resources or variable scopes."
            return
        }
        busy = true
        defer { busy = false }
        do {
            async let incoming = sourceClient.environmentVariables(of: source.resource.route.variableOwner)
            async let existing = destinationClient.environmentVariables(of: destination.resource.route.variableOwner)
            let values = try await (incoming, existing)
            plan = try VariableSyncPlan(
                source: values.0, destination: values.1, sourcePreview: sourcePreview,
                destinationPreview: destinationPreview,
                destinationIsApplication: destination.resource.kind == .application)
        } catch {
            message = "Could not compare variables. Check the connections and token permissions, then try again."
        }
    }

    func apply(
        source: VariableSyncEndpoint, destination: VariableSyncEndpoint, sourceClient: CoolifyClient,
        destinationClient: CoolifyClient, sourcePreview: Bool
    ) async {
        guard let plan, reviewing, !busy, !writes.isEmpty else { return }
        let changes = writes
        busy = true
        defer {
            busy = false
            reviewing = false
            self.plan = nil
            selected = []
            matchDestination = false
        }
        do {
            let sourceNow = try await sourceClient.environmentVariables(of: source.resource.route.variableOwner).filter
            { $0.isPreview == sourcePreview }
            guard Set(sourceNow) == Set(plan.source) else {
                message = "Source variables changed after comparison. Compare again before applying."
                return
            }
            let result = try await destinationClient.applyVariableSync(
                changes, plan: plan, to: destination.resource.route.variableOwner)
            if !result.appliedKeys.isEmpty {
                changedDestination = destination
                changedPreview = plan.destinationPreview
            }
            if let failed = result.failedKey {
                message =
                    "\(result.appliedKeys.count) changes confirmed. The write for \(failed) could not be confirmed; remaining writes were stopped. Compare again to inspect the actual destination before retrying."
            } else {
                message = "\(result.appliedKeys.count) changes saved to \(destination.label)."
            }
        } catch {
            message =
                "The destination could not be verified or changed after comparison. Compare again before applying."
        }
    }

    func activate(client: CoolifyClient, endpoint: VariableSyncEndpoint) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            switch endpoint.resource.route {
            case .application(let uuid): _ = try await client.deploy(uuid: uuid)
            case .database(let uuid): _ = try await client.restartDatabase(uuid)
            case .service(let uuid): _ = try await client.restartService(uuid)
            }
            changedDestination = nil
            message =
                "\(endpoint.resource.kind == .application ? "Redeploy" : "Restart") requested for \(endpoint.label)."
        } catch { message = "The action could not be confirmed. Check the resource before trying again." }
    }
}

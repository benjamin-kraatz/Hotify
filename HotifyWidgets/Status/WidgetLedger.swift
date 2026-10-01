import Foundation

/// What the widgets remember between timelines, in the App Group: the last reading of each resource, the actions
/// they sent that Coolify has not finished, and a stop that waits for its second tap.
struct WidgetLedger: Codable {
    var readings: [String: ResourceReading] = [:]
    var transitions: [String: ResourceTransition] = [:]
    var armedStop: ArmedStop?
    /// An action Coolify refused, shown on its resource for a little while.
    var failures: [String: ActionFailure] = [:]
    /// The last count of each instance, by instance id, for when Coolify cannot be reached.
    var pulses: [String: InstancePulse] = [:]

    /// How long a stop waits for the second tap.
    static let armDuration: TimeInterval = 6
    /// A widget may still show the armed button a moment after it expired, until its next entry lands.
    private static let armGrace: TimeInterval = 2
    private static let failureDuration: TimeInterval = 120
    private static let key = "hotify.widgets.ledger"

    static func load() -> WidgetLedger {
        guard let data = AppGroup.defaults.data(forKey: key),
            let ledger = try? JSONDecoder().decode(WidgetLedger.self, from: data)
        else { return WidgetLedger() }
        return ledger
    }

    /// Loads, changes, and saves in one go. Widgets and controls run in one process, so this is enough.
    @discardableResult
    static func update<T>(_ change: (inout WidgetLedger) -> T) -> T {
        var ledger = load()
        let result = change(&ledger)
        ledger.prune()
        if let data = try? JSONEncoder().encode(ledger) {
            AppGroup.defaults.set(data, forKey: key)
        }
        return result
    }

    func isArmed(_ pinID: String, at date: Date = .now) -> Bool {
        guard let armedStop, armedStop.pinID == pinID else { return false }
        return date < armedStop.until
    }

    /// Arms a stop, or reports that it already was and clears it, so the caller can go ahead.
    mutating func confirmStop(_ pinID: String, now: Date = .now) -> Bool {
        if let armedStop, armedStop.pinID == pinID, now < armedStop.until.addingTimeInterval(Self.armGrace) {
            self.armedStop = nil
            return true
        }
        armedStop = ArmedStop(pinID: pinID, until: now.addingTimeInterval(Self.armDuration))
        return false
    }

    func failure(for pinID: String, at date: Date = .now) -> ActionFailure? {
        guard let failure = failures[pinID], date < failure.at.addingTimeInterval(Self.failureDuration) else {
            return nil
        }
        return failure
    }

    /// Folds fresh readings in and ends every transition whose resource got where it was going.
    mutating func absorb(_ fresh: [String: ResourceReading], now: Date = .now) {
        readings.merge(fresh) { _, new in new }
        for (id, reading) in fresh where reading.problem == nil {
            guard var transition = transitions[id] else { continue }
            if transition.observe(status: reading.status, isDeploying: reading.isDeploying, now: now) == nil {
                transitions[id] = transition
            } else {
                transitions[id] = nil
            }
        }
    }

    private mutating func prune(now: Date = .now) {
        if let armedStop, now > armedStop.until.addingTimeInterval(Self.armGrace) {
            self.armedStop = nil
        }
        failures = failures.filter { now < $0.value.at.addingTimeInterval(Self.failureDuration) }
        // A transition outlives its resource's widget only until Coolify would have given up on it anyway.
        transitions = transitions.filter { now.timeIntervalSince($0.value.startedAt) < 600 }
        readings = readings.filter { reading in
            reading.value.checkedAt.map { now.timeIntervalSince($0) < 7 * 86_400 } ?? true
        }
    }
}

/// A stop the user tapped once.
struct ArmedStop: Codable, Hashable {
    var pinID: String
    var until: Date
}

/// An action Coolify did not accept.
struct ActionFailure: Codable, Hashable {
    var action: ResourceAction
    var at: Date

    var message: String {
        switch action {
        case .start: "Couldn't start"
        case .deploy: "Couldn't deploy"
        case .restart: "Couldn't restart"
        case .stop: "Couldn't stop"
        case .cancelDeployment: "Couldn't cancel"
        }
    }
}

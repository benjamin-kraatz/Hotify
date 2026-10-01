import Foundation

/// One pinned resource as a widget draws it: its flame, its status, and what can be done from the widget.
struct PinTile: Identifiable, Hashable {
    var pin: ResourcePin
    var name: String
    var subtitle: String?
    /// The instance the resource lives on, for lists that span several.
    var instanceName: String
    var heat: Heat
    var status: String
    /// The status is a problem, a failed action, or a heat that wants a look. It glows amber.
    var isAlert: Bool
    var checkedAt: Date?
    /// Every action that makes sense now, most likely first.
    var actions: [ResourceAction]
    /// The one action a small tile has room for.
    var primary: ResourceAction?
    /// The stop is waiting for its second tap.
    var isArmed: Bool

    var id: String { pin.id }
    var kind: ResourceKind { pin.route.kind }

    init(pin: ResourcePin, fallbackName: String, ledger: WidgetLedger, at date: Date) {
        self.pin = pin
        let reading = ledger.readings[pin.id]
        let pending = ledger.transitions[pin.id]?.action
        let failure = ledger.failure(for: pin.id, at: date)
        name = reading.flatMap { $0.name.isEmpty ? nil : $0.name } ?? fallbackName
        subtitle = reading?.subtitle
        instanceName = reading?.instanceName ?? ""
        checkedAt = reading?.checkedAt
        isArmed = ledger.isArmed(pin.id, at: date)

        guard let reading, reading.checkedAt != nil else {
            heat = .unknown
            status = reading?.problem?.message(instanceName: reading?.instanceName ?? "") ?? "Waiting for Coolify"
            isAlert = reading?.problem != nil
            actions = []
            primary = nil
            return
        }
        let summary = reading.summary(for: pin.route)
        if let problem = reading.problem {
            heat = .unknown
            status = problem.message(instanceName: reading.instanceName)
            isAlert = true
            actions = []
            primary = nil
            return
        }
        heat = summary.heat(pendingAction: pending)
        if let failure, pending == nil {
            status = failure.message
            isAlert = true
        } else {
            status = StatusLabel.text(for: summary, pendingAction: pending)
            isAlert = heat.needsAttention
        }
        actions = pending == nil ? ResourceAction.available(for: summary) : []
        primary = pending == nil ? Self.primary(for: summary, among: actions) : nil
    }

    /// Start a cold resource, stop a running one, restart a sick one, and cancel a build.
    private static func primary(for summary: ResourceSummary, among actions: [ResourceAction]) -> ResourceAction? {
        let choice: ResourceAction? =
            if summary.isDeploying {
                .cancelDeployment
            } else {
                switch summary.heat {
                case .cold: .start
                case .lit: .stop
                case .troubled: .restart
                case .warming, .unknown: nil
                }
            }
        return choice.flatMap { actions.contains($0) ? $0 : nil }
    }
}

extension PinTile {
    /// A tile with plain values, for previews and the widget gallery.
    init(
        sample name: String, kind: ResourceRoute, subtitle: String?, heat: Heat, status: String,
        primary: ResourceAction?, actions: [ResourceAction], isArmed: Bool = false
    ) {
        pin = ResourcePin(instanceID: UUID(), route: kind)
        self.name = name
        self.subtitle = subtitle
        instanceName = "homelab"
        self.heat = heat
        self.status = status
        isAlert = heat.needsAttention
        checkedAt = .now.addingTimeInterval(-240)
        self.actions = actions
        self.primary = primary
        self.isArmed = isArmed
    }

    static let samples: [PinTile] = [
        PinTile(
            sample: "plausible", kind: .service("s1"), subtitle: "4 containers", heat: .lit, status: "Running",
            primary: .stop, actions: [.restart, .stop]),
        PinTile(
            sample: "api", kind: .application("a1"), subtitle: "api.example.com", heat: .lit, status: "Healthy",
            primary: .stop, actions: [.deploy, .restart, .stop]),
        PinTile(
            sample: "web", kind: .application("a2"), subtitle: "example.com", heat: .warming, status: "Deploying…",
            primary: .cancelDeployment, actions: [.cancelDeployment]),
        PinTile(
            sample: "postgres", kind: .database("d1"), subtitle: "PostgreSQL", heat: .cold, status: "Exited",
            primary: .start, actions: [.start]),
        PinTile(
            sample: "worker", kind: .application("a3"), subtitle: "acme/worker", heat: .troubled, status: "Unhealthy",
            primary: .restart, actions: [.deploy, .restart, .stop]),
        PinTile(
            sample: "redis", kind: .database("d2"), subtitle: "Redis", heat: .lit, status: "Healthy",
            primary: .stop, actions: [.restart, .stop]),
    ]
}

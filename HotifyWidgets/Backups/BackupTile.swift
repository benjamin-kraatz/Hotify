import Foundation

/// One database's backups as a widget draws them.
struct BackupTile: Identifiable, Hashable {
    var pin: ResourcePin
    var name: String
    var engine: String?
    var heat: Heat
    var status: String
    var isAlert: Bool
    /// When the shown status happened: the newest run, or the last good one when that is what matters.
    var date: Date?
    /// Back Up Now runs this configuration. `nil` hides the button.
    var backupUUID: String?

    var id: String { pin.id }
    var link: URL { ResourceLink(instanceID: pin.instanceID, route: pin.route, place: .backups).url }

    /// How long a sent backup shows as underway before the widget stops waiting for it.
    private static let requestPatience: TimeInterval = 600

    init(pin: ResourcePin, fallbackName: String, ledger: WidgetLedger, at now: Date) {
        self.pin = pin
        let reading = ledger.backups[pin.id]
        name = reading.flatMap { $0.name.isEmpty ? nil : $0.name } ?? fallbackName
        engine = reading?.engine
        backupUUID = nil
        date = nil

        guard let reading, reading.checkedAt != nil, reading.problem == nil else {
            heat = .unknown
            status = reading?.problem?.message(instanceName: reading?.instanceName ?? "") ?? "Waiting for Coolify"
            isAlert = reading?.problem != nil
            return
        }
        let request = ledger.backupRequests[pin.id]
        let lastRunStatus = reading.lastStatus ?? ""
        let isRunning = ["running", "in_progress", "queued"].contains(lastRunStatus)
        let isRequested =
            request.map { request in
                !request.failed && now.timeIntervalSince(request.at) < Self.requestPatience
                    && (reading.lastRunAt ?? .distantPast) < request.at.addingTimeInterval(-60)
            } ?? false
        backupUUID = isRunning || isRequested ? nil : reading.backupUUID
        date = reading.lastRunAt

        if let request, request.failed, now.timeIntervalSince(request.at) < 120 {
            (heat, status, isAlert) = (.troubled, "Couldn't back up", true)
        } else if isRunning || isRequested {
            (heat, status, isAlert) = (.warming, "Backing up…", true)
        } else if reading.configurations == 0 {
            (heat, status, isAlert) = (.cold, "No backups", false)
        } else if lastRunStatus == "failed" || lastRunStatus == "error" {
            (heat, status, isAlert) = (.troubled, "Failed", true)
        } else if reading.isOverdue(at: now) {
            (heat, status, isAlert) = (.troubled, "Overdue", true)
            date = reading.lastSuccessAt
        } else if reading.enabledConfigurations == 0 {
            (heat, status, isAlert) = (.cold, "Schedule off", false)
        } else if reading.lastSuccessAt != nil {
            (heat, status, isAlert) = (.lit, "Backed up", false)
        } else {
            (heat, status, isAlert) = (.cold, "No runs yet", false)
        }
    }

    /// Failing before busy before quiet, then the oldest backup first.
    static func urgency(_ lhs: BackupTile, _ rhs: BackupTile) -> Bool {
        func rank(_ heat: Heat) -> Int {
            switch heat {
            case .troubled, .unknown: 0
            case .warming: 1
            case .cold: 2
            case .lit: 3
            }
        }
        if rank(lhs.heat) != rank(rhs.heat) { return rank(lhs.heat) < rank(rhs.heat) }
        return (lhs.date ?? .distantPast) < (rhs.date ?? .distantPast)
    }
}

extension BackupTile {
    /// A tile with plain values, for previews and the widget gallery.
    init(sample name: String, engine: String, heat: Heat, status: String, hoursAgo: Double) {
        pin = ResourcePin(instanceID: UUID(), route: .database(name))
        self.name = name
        self.engine = engine
        self.heat = heat
        self.status = status
        isAlert = heat == .troubled || heat == .warming
        // A database without a configuration has no runs and nothing for Back Up Now to run.
        let isConfigured = status != "No backups"
        date = isConfigured ? .now.addingTimeInterval(-hoursAgo * 3_600) : nil
        backupUUID = heat == .warming || !isConfigured ? nil : "backup"
    }

    static let samples: [BackupTile] = [
        BackupTile(sample: "billing-db", engine: "PostgreSQL", heat: .troubled, status: "Failed", hoursAgo: 3),
        BackupTile(sample: "analytics", engine: "ClickHouse", heat: .troubled, status: "Overdue", hoursAgo: 52),
        BackupTile(sample: "app-db", engine: "PostgreSQL", heat: .lit, status: "Backed up", hoursAgo: 5),
        BackupTile(sample: "cache", engine: "Redis", heat: .warming, status: "Backing up…", hoursAgo: 0.1),
        BackupTile(sample: "cms", engine: "MySQL", heat: .lit, status: "Backed up", hoursAgo: 9),
        BackupTile(sample: "search", engine: "MongoDB", heat: .cold, status: "No backups", hoursAgo: 0),
    ]
}

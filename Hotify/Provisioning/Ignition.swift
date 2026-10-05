import CoolifyAPI
import Foundation

/// A new service or database on its way up, from the start request until every container runs.
struct Ignition: Hashable {
    enum Phase: Hashable {
        case starting
        case running
        /// Still not up after several minutes. Often a large image still pulling, so it keeps watching.
        case stalled
        /// It came up, then every container stopped again.
        case stopped
    }

    var startedAt: Date
    var containers: [ContainerSummary] = []
    var phase: Phase = .starting
    /// Coolify reports a service as exited for a few seconds before it starts. Only after something moved does
    /// an exited service count as stopped.
    private var sawActivity = false

    /// How long a first start may take before Hotify says so. Pulling images for a large template takes minutes.
    static let patience: TimeInterval = 300

    init(startedAt: Date = .now, containers: [ContainerSummary] = [], phase: Phase = .starting) {
        self.startedAt = startedAt
        self.containers = containers
        self.phase = phase
    }

    var heat: Heat {
        switch phase {
        case .starting: .warming
        case .running: .lit
        case .stalled, .stopped: .troubled
        }
    }

    mutating func observe(_ service: Service, at now: Date = .now) {
        let applications = service.applications ?? []
        let databases = service.databases ?? []
        let members = applications + databases
        containers = members.enumerated().map { index, container in
            ContainerSummary(
                // Applications and databases are numbered in separate tables, so their ids can collide.
                id: index < applications.count ? container.id : -container.id - 1,
                name: container.humanName ?? container.name,
                serviceName: container.name,
                status: container.status,
                image: container.image
            )
        }
        let counted = members.filter { $0.excludeFromStatus != true }.map { Heat(status: $0.status) }
        observe(counted, overall: Heat(status: service.status), at: now)
    }

    /// A database is its own one container.
    mutating func observe(_ database: Database, name: String, at now: Date = .now) {
        containers = [ContainerSummary(id: 0, name: name, status: database.status)]
        observe([Heat(status: database.status)], overall: Heat(status: database.status), at: now)
    }

    /// An application is its own one container. A build that has not started yet stays in `.starting`.
    mutating func observe(_ application: Application, name: String, at now: Date = .now) {
        containers = [ContainerSummary(id: 0, name: name, status: application.status)]
        observe([Heat(status: application.status)], overall: Heat(status: application.status), at: now)
    }

    private mutating func observe(_ counted: [Heat], overall: Heat, at now: Date) {
        let heats = counted.isEmpty ? [overall] : counted

        if heats.allSatisfy({ $0 == .lit }) {
            phase = .running
            return
        }
        if heats.contains(where: { $0 == .lit || $0 == .warming }) || overall == .warming {
            sawActivity = true
        }
        let elapsed = now.timeIntervalSince(startedAt)
        if sawActivity, heats.allSatisfy({ $0 == .cold }), elapsed > 20 {
            phase = .stopped
        } else if elapsed > Self.patience {
            phase = .stalled
        } else {
            phase = .starting
        }
    }
}

import CoolifyAPI
import Foundation

/// How much of one instance runs, counted from every application, database, and service on it.
struct InstancePulse: Codable, Hashable {
    var instanceName: String
    var running: Int
    /// Starting, deploying, unhealthy, or degraded.
    var attention: Int
    var total: Int
    /// Names of what wants a look, most important first.
    var attentionNames: [String] = []
    var checkedAt: Date?
    var problem: ReadingProblem?

    /// One heat per resource, hottest first, for a `HeatStrip`.
    var heats: [Heat] {
        Array(repeating: Heat.lit, count: running) + Array(repeating: .troubled, count: attention)
            + Array(repeating: .cold, count: max(0, total - running - attention))
    }

    /// The flame for the whole instance: amber if anything wants a look, lit if anything runs.
    var heat: Heat {
        if problem != nil || checkedAt == nil { return .unknown }
        if attention > 0 { return .troubled }
        return running > 0 ? .lit : .cold
    }

    init(instanceName: String, resources: [ResourceSummary], checkedAt: Date) {
        self.instanceName = instanceName
        let heats = resources.map { $0.heat(pendingAction: nil) }
        running = heats.filter { $0 == .lit }.count
        attention = heats.filter(\.needsAttention).count
        total = resources.count
        attentionNames = resources.filter { $0.heat(pendingAction: nil).needsAttention }.map(\.name)
        self.checkedAt = checkedAt
    }

    init(instanceName: String, problem: ReadingProblem) {
        self.instanceName = instanceName
        running = 0
        attention = 0
        total = 0
        self.problem = problem
    }

    /// Reads every resource on an instance. A failed read keeps the last count, marked with its problem.
    static func read(_ instanceID: UUID, previous: InstancePulse?) async -> InstancePulse {
        switch InstanceAccess.client(for: instanceID) {
        case .failure(let error):
            return failed(previous, name: InstanceAccess.instance(instanceID)?.name ?? "", problem: error.problem)
        case .success((let instance, let client)):
            do {
                async let applications = client.applications()
                async let databases = client.databases()
                async let services = client.services()
                async let deployments = try? client.runningDeployments()
                let found = try await (applications, databases, services)
                let queue = (await deployments ?? []).filter { !$0.isPreview }
                let resources =
                    found.0.map { application in
                        ResourceSummary(
                            application: application,
                            activeDeployment: queue.first {
                                application.id != nil && $0.applicationID == application.id
                            })
                    } + found.1.map { ResourceSummary(database: $0) } + found.2.map { ResourceSummary(service: $0) }
                return InstancePulse(instanceName: instance.name, resources: resources, checkedAt: .now)
            } catch {
                return failed(previous, name: instance.name, problem: .unreachable)
            }
        }
    }

    private static func failed(_ last: InstancePulse?, name: String, problem: ReadingProblem) -> InstancePulse {
        guard var last else { return InstancePulse(instanceName: name, problem: problem) }
        last.problem = problem
        if !name.isEmpty { last.instanceName = name }
        return last
    }
}

extension InstancePulse {
    static let sample: InstancePulse = {
        var pulse = InstancePulse(instanceName: "homelab", problem: .unreachable)
        pulse.problem = nil
        pulse.running = 9
        pulse.attention = 1
        pulse.total = 12
        pulse.attentionNames = ["worker"]
        pulse.checkedAt = .now.addingTimeInterval(-300)
        return pulse
    }()
}

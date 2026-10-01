import CoolifyAPI
import Foundation

/// Reads pinned resources from Coolify: one request per resource, plus the deployment queue when an application is
/// pinned.
enum ResourceProbe {
    /// Fresh readings by pin id. A failed read keeps the last good one, marked with its problem.
    static func read(_ pins: [ResourcePin], previous: [String: ResourceReading]) async -> [String: ResourceReading] {
        let byInstance = Dictionary(grouping: pins, by: \.instanceID)
        return await withTaskGroup(of: [String: ResourceReading].self) { group in
            for (instanceID, pins) in byInstance {
                group.addTask { await read(pins, on: instanceID, previous: previous) }
            }
            var readings: [String: ResourceReading] = [:]
            for await batch in group {
                readings.merge(batch) { _, new in new }
            }
            return readings
        }
    }

    private static func read(
        _ pins: [ResourcePin], on instanceID: UUID, previous: [String: ResourceReading]
    ) async -> [String: ResourceReading] {
        let client: CoolifyClient
        let instance: CoolifyInstance
        switch InstanceAccess.client(for: instanceID) {
        case .success(let access):
            (instance, client) = access
        case .failure(let error):
            let name = InstanceAccess.instance(instanceID)?.name ?? ""
            return Dictionary(
                uniqueKeysWithValues: pins.map { pin in
                    (pin.id, failed(previous[pin.id], name: name, problem: error.problem))
                })
        }

        // The queue only adds a "Deploying" state. Without it the resources still read.
        let deployments: [Deployment]
        if pins.contains(where: { $0.route.kind == .application }) {
            deployments = ((try? await client.runningDeployments()) ?? []).filter { !$0.isPreview }
        } else {
            deployments = []
        }

        return await withTaskGroup(of: (String, ResourceReading).self) { group in
            for pin in pins {
                group.addTask {
                    do {
                        let summary = try await summary(of: pin.route, client: client, deployments: deployments)
                        return (pin.id, ResourceReading(summary: summary, instanceName: instance.name, checkedAt: .now))
                    } catch let error as CoolifyError where error.statusCode == 404 {
                        return (pin.id, failed(previous[pin.id], name: instance.name, problem: .gone))
                    } catch {
                        return (pin.id, failed(previous[pin.id], name: instance.name, problem: .unreachable))
                    }
                }
            }
            var readings: [String: ResourceReading] = [:]
            for await (id, reading) in group {
                readings[id] = reading
            }
            return readings
        }
    }

    private static func summary(
        of route: ResourceRoute, client: CoolifyClient, deployments: [Deployment]
    ) async throws -> ResourceSummary {
        switch route {
        case .application(let uuid):
            let application = try await client.application(uuid)
            let active = deployments.first { application.id != nil && $0.applicationID == application.id }
            return ResourceSummary(application: application, activeDeployment: active)
        case .database(let uuid):
            return ResourceSummary(database: try await client.database(uuid))
        case .service(let uuid):
            return ResourceSummary(service: try await client.service(uuid))
        }
    }

    private static func failed(_ last: ResourceReading?, name: String, problem: ReadingProblem) -> ResourceReading {
        guard var last else { return ResourceReading(name: "", instanceName: name, problem: problem) }
        last.problem = problem
        if !name.isEmpty { last.instanceName = name }
        return last
    }
}

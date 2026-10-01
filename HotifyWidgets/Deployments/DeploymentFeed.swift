import CoolifyAPI
import Foundation

/// Reads the newest deployments of the followed applications, previews included.
///
/// Coolify has no history across an instance, only per application, so each followed application is its own
/// request. A widget that follows nothing in particular follows the first applications it finds, up to a limit.
enum DeploymentFeed {
    /// How many recent deployments to ask for per application.
    static let perApplication = 5
    /// How many applications a widget follows when none were picked.
    static let automaticLimit = 12

    struct Followed {
        var pin: ResourcePin
        var name: String
    }

    struct Feed {
        var items: [DeploymentItem]
        var problems: [String]
        var followed: Int
        /// Applications there were to follow, when the widget picked them itself.
        var available: Int?
    }

    static func read(picked: [ResourceEntity]) async -> Feed {
        var followed = picked.compactMap { entity in entity.pin.map { Followed(pin: $0, name: entity.name) } }
            .filter { $0.pin.route.kind == .application }
        var available: Int?
        if followed.isEmpty {
            let all = await allApplications()
            available = all.count
            followed = Array(all.prefix(automaticLimit))
        }

        let cached = WidgetLedger.load().histories
        let byInstance = Dictionary(grouping: followed, by: \.pin.instanceID)
        let batches = await withTaskGroup(of: Batch.self) { group in
            for (instanceID, applications) in byInstance {
                group.addTask { await read(applications, on: instanceID) }
            }
            var batches: [Batch] = []
            for await batch in group {
                batches.append(batch)
            }
            return batches
        }
        let fresh = batches.reduce(into: [String: [DeploymentItem]]()) { $0.merge($1.histories) { _, new in new } }
        WidgetLedger.update { $0.histories.merge(fresh) { _, new in new } }

        // An application that could not be read this time shows what it showed last time.
        let items = followed.flatMap { fresh[$0.pin.id] ?? cached[$0.pin.id] ?? [] }
            .sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
        return Feed(
            items: items, problems: batches.compactMap(\.problem).sorted(), followed: followed.count,
            available: available)
    }

    private struct Batch {
        var histories: [String: [DeploymentItem]] = [:]
        var problem: String?
    }

    private static func read(_ applications: [Followed], on instanceID: UUID) async -> Batch {
        guard case .success((let instance, let client)) = InstanceAccess.client(for: instanceID) else {
            let name = InstanceAccess.instance(instanceID)?.name ?? ""
            return Batch(problem: ReadingProblem.noToken.message(instanceName: name))
        }
        return await withTaskGroup(of: (String, [DeploymentItem]?).self) { group in
            for application in applications {
                group.addTask {
                    let page = try? await client.applicationDeployments(
                        application.pin.route.uuid, take: perApplication)
                    return (
                        application.pin.id,
                        page?.deployments.map {
                            DeploymentItem(
                                $0, pinID: application.pin.id,
                                applicationName: application.name, instanceName: instance.name)
                        }
                    )
                }
            }
            var batch = Batch()
            var failed = 0
            for await (id, items) in group {
                if let items { batch.histories[id] = items } else { failed += 1 }
            }
            if failed > 0, batch.histories.isEmpty {
                batch.problem = ReadingProblem.unreachable.message(instanceName: instance.name)
            }
            return batch
        }
    }

    /// Every application on every saved instance, one request per instance.
    private static func allApplications() async -> [Followed] {
        let instances = AppGroup.instances()
        return await withTaskGroup(of: (Int, [Followed]).self) { group in
            for (index, instance) in instances.enumerated() {
                group.addTask {
                    guard case .success((_, let client)) = InstanceAccess.client(for: instance.id),
                        let applications = try? await client.applications()
                    else { return (index, []) }
                    let followed = applications.map { application in
                        Followed(
                            pin: ResourcePin(instanceID: instance.id, route: .application(application.uuid)),
                            name: application.name.isEmpty ? application.uuid : application.name)
                    }
                    return (index, followed)
                }
            }
            var found: [(Int, [Followed])] = []
            for await result in group {
                found.append(result)
            }
            return found.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
    }
}

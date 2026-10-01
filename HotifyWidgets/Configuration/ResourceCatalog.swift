import CoolifyAPI
import Foundation

/// Every resource on every saved instance, grouped for the widget editor. The last list is cached in the App Group,
/// so a widget finds its picks by id without asking Coolify.
enum ResourceCatalog {
    struct Group {
        var title: String
        var entities: [ResourceEntity]
    }

    private static let key = "hotify.widgets.catalog"

    static func cached() -> [String: ResourceEntity] {
        guard let data = AppGroup.defaults.data(forKey: key),
            let entities = try? JSONDecoder().decode([ResourceEntity].self, from: data)
        else { return [:] }
        return Dictionary(entities.map { ($0.id, $0) }) { first, _ in first }
    }

    /// One group per instance, applications first, then services, then databases.
    static func load() async -> [Group] {
        let instances = AppGroup.instances()
        let groups = await withTaskGroup(of: (Int, Group?).self) { group in
            for (index, instance) in instances.enumerated() {
                group.addTask { (index, await load(instance)) }
            }
            var loaded: [(Int, Group?)] = []
            for await result in group {
                loaded.append(result)
            }
            return loaded.sorted { $0.0 < $1.0 }.compactMap(\.1)
        }
        var cache = cached()
        for entity in groups.flatMap(\.entities) {
            cache[entity.id] = entity
        }
        if let data = try? JSONEncoder().encode(Array(cache.values)) {
            AppGroup.defaults.set(data, forKey: key)
        }
        return groups
    }

    private static func load(_ instance: CoolifyInstance) async -> Group? {
        guard case .success((_, let client)) = InstanceAccess.client(for: instance.id) else { return nil }
        do {
            async let applications = client.applications()
            async let databases = client.databases()
            async let services = client.services()
            async let places = places(client)
            let found = try await (applications, databases, services)
            let index = await places
            let resources =
                found.0.map { ResourceSummary(application: $0, place: $0.environmentID.flatMap { index[$0] }) }
                + found.1.map { ResourceSummary(database: $0, place: $0.environmentID.flatMap { index[$0] }) }
                + found.2.map { ResourceSummary(service: $0, place: $0.environmentID.flatMap { index[$0] }) }
            let entities = resources.sortedForDisplay().map { resource in
                ResourceEntity(
                    id: ResourcePin(instanceID: instance.id, route: resource.route).id,
                    name: resource.name,
                    instanceName: instance.name,
                    place: resource.place.map { "\($0.projectName) · \($0.environmentName)" }
                )
            }
            return Group(title: instance.name, entities: entities)
        } catch {
            return nil
        }
    }

    /// Project and environment names. The project list omits environments, so each project is its own request.
    private static func places(_ client: CoolifyClient) async -> [Int: ResourcePlace] {
        guard let projects = try? await client.projects() else { return [:] }
        let detailed = await withTaskGroup(of: Project?.self) { group in
            for project in projects {
                group.addTask { try? await client.project(project.uuid) }
            }
            var loaded: [Project] = []
            for await project in group {
                if let project { loaded.append(project) }
            }
            return loaded
        }
        return ResourcePlace.index(detailed)
    }
}

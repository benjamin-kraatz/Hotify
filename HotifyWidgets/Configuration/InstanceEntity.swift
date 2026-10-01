import AppIntents
import CoolifyAPI
import Foundation

/// A saved Coolify instance, to pick for the instance widget.
struct InstanceEntity: AppEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Instance")
    static let defaultQuery = InstanceQuery()

    var id: UUID
    var name: String
    var host: String

    init(_ instance: CoolifyInstance) {
        id = instance.id
        name = instance.name
        host = instance.baseURL.host() ?? instance.baseURL.absoluteString
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(host)")
    }
}

/// The instances the app saved. No network: the list comes from the App Group.
struct InstanceQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [InstanceEntity] {
        AppGroup.instances().filter { identifiers.contains($0.id) }.map(InstanceEntity.init)
    }

    func suggestedEntities() async throws -> [InstanceEntity] {
        AppGroup.instances().map(InstanceEntity.init)
    }

    /// The first instance, so a new widget shows something before anyone edits it.
    func defaultResult() async -> InstanceEntity? {
        AppGroup.instances().first.map(InstanceEntity.init)
    }
}

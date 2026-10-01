import AppIntents
import Foundation

/// An application, database, or service to pick for a widget or control.
struct ResourceEntity: AppEntity, Codable, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Resource")
    static let defaultQuery = ResourceQuery()

    /// A `ResourcePin` id.
    var id: String
    var name: String
    var instanceName: String
    /// `Project · environment`, when Coolify told us.
    var place: String?

    var pin: ResourcePin? { ResourcePin(id: id) }

    var displayRepresentation: DisplayRepresentation {
        let kind = pin?.route.kind
        let detail = [place, instanceName].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
        return DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(detail.isEmpty ? (kind?.title ?? "") : detail)",
            image: DisplayRepresentation.Image(systemName: kind?.systemImage ?? "flame")
        )
    }
}

/// Lists every resource on every saved instance, and finds picked ones again without the network.
struct ResourceQuery: EntityStringQuery {
    func entities(for identifiers: [ResourceEntity.ID]) async throws -> [ResourceEntity] {
        let known = ResourceCatalog.cached()
        let readings = WidgetLedger.load().readings
        return identifiers.compactMap { id in
            if let entity = known[id] { return entity }
            // A pick from before the catalog was cached, or from another device. Show what the widgets last read.
            guard ResourcePin(id: id) != nil else { return nil }
            let reading = readings[id]
            return ResourceEntity(
                id: id, name: reading?.name ?? "Resource", instanceName: reading?.instanceName ?? "", place: nil)
        }
    }

    func entities(matching string: String) async throws -> IntentItemCollection<ResourceEntity> {
        let groups = await ResourceCatalog.load()
        let filtered = groups.map { group in
            (group.title, group.entities.filter { $0.name.localizedStandardContains(string) })
        }
        return collection(filtered.filter { !$0.1.isEmpty })
    }

    func suggestedEntities() async throws -> IntentItemCollection<ResourceEntity> {
        let groups = await ResourceCatalog.load()
        return collection(groups.map { ($0.title, $0.entities) })
    }

    private func collection(_ groups: [(String, [ResourceEntity])]) -> IntentItemCollection<ResourceEntity> {
        IntentItemCollection(
            sections: groups.map { title, entities in
                IntentItemSection(LocalizedStringResource(stringLiteral: title), items: entities)
            })
    }
}

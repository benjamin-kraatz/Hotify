import CoolifyAPI
import Foundation

/// The database a restore writes into, with what the sheet and the banner need to name it.
struct RestoreTarget: Hashable {
    var importTarget: DatabaseImportTarget
    var name: String
    /// `nil` when Coolify cannot import into this database's engine.
    var engine: DatabaseImportEngine?
    /// What the database runs, such as `Redis` or `redis:7-alpine`, for an engine Coolify cannot import into.
    var engineDescription: String?
    /// The service a database container belongs to.
    var serviceName: String?
    var status: String?

    var engineName: String {
        engine?.displayName ?? engineDescription ?? "an unknown engine"
    }

    var isServiceDatabase: Bool {
        if case .serviceDatabase = importTarget { return true }
        return false
    }

    /// Coolify only imports into a running database. An unknown status lets Coolify decide.
    var isKnownStopped: Bool {
        guard let status, !status.isEmpty else { return false }
        return ResourceStatus(raw: status).state != "running"
    }
}

extension RestoreTarget {
    /// A standalone database, from its Coolify type such as `standalone-postgresql`.
    init(database uuid: String, name: String, databaseType: String?, engineDescription: String?, status: String?) {
        self.init(
            importTarget: .database(uuid),
            name: name,
            engine: DatabaseImportEngine(databaseType: databaseType),
            engineDescription: engineDescription ?? databaseType,
            status: status
        )
    }

    /// A database container inside a service. Coolify reads its engine from the image.
    init(container: ContainerSummary, service uuid: String, serviceName: String?) {
        self.init(
            importTarget: .serviceDatabase(service: uuid, database: container.uuid),
            name: container.name,
            engine: DatabaseImportEngine(serviceImage: container.image),
            engineDescription: container.image,
            serviceName: serviceName,
            status: container.status
        )
    }
}

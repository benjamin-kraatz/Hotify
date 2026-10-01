import Foundation

/// Which of Coolify's three resource types something is.
enum ResourceKind: CaseIterable, Hashable {
    case application
    case database
    case service

    var title: String {
        switch self {
        case .application: "Application"
        case .database: "Database"
        case .service: "Service"
        }
    }

    var pluralTitle: String {
        switch self {
        case .application: "Applications"
        case .database: "Databases"
        case .service: "Services"
        }
    }

    var systemImage: String {
        switch self {
        case .application: "shippingbox"
        case .database: "cylinder.split.1x2"
        case .service: "square.stack.3d.up"
        }
    }
}

/// The application, database, or service open on the detail screen.
enum ResourceRoute: Hashable {
    case application(String)
    case database(String)
    case service(String)

    var kind: ResourceKind {
        switch self {
        case .application: .application
        case .database: .database
        case .service: .service
        }
    }

    var uuid: String {
        switch self {
        case .application(let uuid), .database(let uuid), .service(let uuid): uuid
        }
    }

    /// The kind as one stable word, for links and saved selections.
    var key: String {
        switch self {
        case .application: "application"
        case .database: "database"
        case .service: "service"
        }
    }

    init?(key: String, uuid: String) {
        guard !uuid.isEmpty else { return nil }
        switch key {
        case "application": self = .application(uuid)
        case "database": self = .database(uuid)
        case "service": self = .service(uuid)
        default: return nil
        }
    }

    var busyTarget: BusyTarget {
        switch self {
        case .application(let uuid): .application(uuid)
        case .database(let uuid): .database(uuid)
        case .service(let uuid): .service(uuid)
        }
    }
}

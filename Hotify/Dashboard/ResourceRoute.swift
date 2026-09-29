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

    var busyTarget: BusyTarget {
        switch self {
        case .application(let uuid): .application(uuid)
        case .database(let uuid): .database(uuid)
        case .service(let uuid): .service(uuid)
        }
    }

    var showsDeployments: Bool {
        kind == .application
    }
}

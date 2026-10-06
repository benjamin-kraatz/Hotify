import CoolifyAPI
import Foundation
import SwiftUI

/// Opens the move, clone, or migrate sheet for the resource on screen.
struct PlacementSheet: View {
    var intent: PlacementIntent
    var resource: ResourceSummary
    var client: CoolifyClient?

    @State private var moveCatalog: MoveCatalog
    @State private var destinations: DestinationCatalog

    init(
        intent: PlacementIntent,
        resource: ResourceSummary,
        client: CoolifyClient?,
        moveCatalog: MoveCatalog? = nil,
        destinations: DestinationCatalog? = nil
    ) {
        self.intent = intent
        self.resource = resource
        self.client = client
        _moveCatalog = State(
            initialValue: moveCatalog
                ?? MoveCatalog(
                    projectUUID: resource.place?.projectID,
                    environmentUUID: resource.place?.environmentUUID,
                    currentEnvironmentUUID: resource.place?.environmentUUID
                ))
        _destinations = State(initialValue: destinations ?? DestinationCatalog())
    }

    var body: some View {
        switch intent {
        case .move:
            MoveSheet(
                resourceName: resource.name, route: resource.route, client: client, catalog: moveCatalog,
                heat: resource.heat, origin: origin)
        case .clone:
            CloneSheet(
                resourceName: resource.name, route: resource.route, client: client, catalog: destinations,
                heat: resource.heat, origin: origin)
        case .migrate:
            MigrateSheet(
                resourceName: resource.name, route: resource.route, client: client, catalog: destinations,
                heat: resource.heat, origin: origin)
        }
    }

    private var origin: String? {
        guard let place = resource.place else { return nil }
        return place.environmentName.isEmpty ? place.projectName : "\(place.projectName) · \(place.environmentName)"
    }
}

extension PlacementOwner {
    init(_ route: ResourceRoute) {
        switch route {
        case .application(let uuid): self = .application(uuid)
        case .database(let uuid): self = .database(uuid)
        case .service(let uuid): self = .service(uuid)
        }
    }
}

func placementFailure(_ error: Error) -> String {
    if let error = error as? CoolifyError {
        return error.summary
    }
    return error.localizedDescription
}

#Preview("Move") {
    PlacementSheet(
        intent: .move,
        resource: ResourceSummary(
            route: .application("app"),
            name: "marketing-site",
            status: "running:healthy",
            place: ResourcePlace(
                projectID: "website",
                projectName: "Website",
                environmentName: "production",
                environmentID: 1,
                environmentUUID: "env-prod"
            )
        ),
        client: nil,
        moveCatalog: MoveCatalog(
            projects: [
                Project(
                    uuid: "website", name: "Website",
                    environments: [
                        Environment(id: 1, uuid: "env-prod", name: "production"),
                        Environment(id: 2, uuid: "env-staging", name: "staging"),
                    ])
            ],
            projectUUID: "website",
            environmentUUID: "env-staging",
            currentEnvironmentUUID: "env-prod"
        )
    )
    .environment(\.placePalette, .preview(projects: ["website": .teal], environments: ["env-staging": .indigo]))
}

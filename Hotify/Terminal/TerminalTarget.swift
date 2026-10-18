import Foundation

/// What a terminal opens a shell in: a resource, and when someone picked one, the container inside it.
struct TerminalTarget: Hashable {
    var route: ResourceRoute
    var resourceName: String
    /// Docker's name for the container, such as `postgres-<service uuid>`. `nil` lets the terminal look, and ask
    /// when it finds more than one.
    var containerName: String?
    /// What the user calls that container.
    var containerTitle: String?

    /// Opens on one of a service's containers.
    static func container(_ container: ContainerSummary, in resource: ResourceSummary) -> TerminalTarget {
        // Coolify names a service's container after its compose service and the service's uuid.
        let name = container.serviceName.isEmpty ? nil : "\(container.serviceName)-\(resource.route.uuid)"
        return TerminalTarget(
            route: resource.route, resourceName: resource.name, containerName: name, containerTitle: container.name)
    }
}

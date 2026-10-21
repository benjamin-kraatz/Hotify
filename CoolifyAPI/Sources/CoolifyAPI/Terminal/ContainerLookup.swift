import Foundation

/// The kind of resource that owns a container, as Coolify's container labels name it.
public enum ContainerOwner: String, Sendable {
    case application
    case service
    case database
}

/// Finds a resource's running containers on its server with the label filters Coolify's own terminal uses.
///
/// Coolify labels what it deploys with `coolify.<kind>Uuid`. Containers from older Coolify versions only carry
/// `coolify.<kind>Id` and a compose project named after the uuid, and an older application's container is named
/// after it. Each filter runs as its own `docker ps`, and the results merge.
public struct ContainerLookup: Sendable {
    public var owner: ContainerOwner
    public var uuid: String
    /// `nil` for production. A preview's containers carry its pull request number.
    public var pullRequest: Int?
    /// A server user other than root runs Docker through sudo, as Coolify does.
    public var usesSudo: Bool

    public init(owner: ContainerOwner, uuid: String, pullRequest: Int? = nil, usesSudo: Bool) {
        self.owner = owner
        self.uuid = uuid
        self.pullRequest = pullRequest
        self.usesSudo = usesSudo
    }

    /// One shell line that prints every matching running container as JSON, one per line.
    public var command: String {
        var filterSets = [
            ["label=coolify.\(owner.rawValue)Uuid=\(uuid)"],
            ["label=coolify.\(owner.rawValue)Id", "label=com.docker.compose.project=\(uuid)"],
        ]
        switch owner {
        case .application:
            filterSets.append(["label=coolify.applicationId", "name=\(uuid)"])
        case .database:
            // A standalone database's container is named after its uuid.
            filterSets.append(["name=\(uuid)"])
        case .service:
            break
        }
        let docker = (usesSudo ? "sudo " : "") + "docker ps --format " + Shell.quote("{{json .}}")
        // Joined with `;`, so a filter that matches nothing doesn't stop the next one.
        return
            filterSets
            .map { filters in docker + " " + filters.map { "--filter " + Shell.quote($0) }.joined(separator: " ") }
            .joined(separator: "; ")
    }

    /// The containers in the command's output, each once, in the order Docker listed them. Skips lines that aren't a
    /// container, such as a warning from sudo.
    public func containers(in output: String) -> [DockerContainer] {
        let decoder = JSONDecoder()
        var seen: Set<String> = []
        var containers: [DockerContainer] = []
        for line in output.split(whereSeparator: \.isNewline) {
            guard let container = try? decoder.decode(DockerContainer.self, from: Data(line.utf8)),
                seen.insert(container.id).inserted,
                belongsToPullRequest(container)
            else { continue }
            containers.append(container)
        }
        return containers
    }

    /// Production containers have `coolify.pullRequestId=0`, or no such label when an older Coolify started them.
    private func belongsToPullRequest(_ container: DockerContainer) -> Bool {
        let label = container.labels["coolify.pullRequestId"].flatMap { Int($0) } ?? 0
        return label == (pullRequest ?? 0)
    }
}

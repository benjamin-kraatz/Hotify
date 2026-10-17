import CoolifyAPI
import Foundation

/// The commands Coolify runs on the server around each deployment of an application, as the Settings tab edits them.
///
/// The container names only matter for a Docker Compose application, which runs one container per service. With one
/// container, Coolify ignores the name, so the tab neither shows nor sends it.
struct ApplicationDeploymentCommands: Hashable {
    var preDeployment = ""
    var preDeploymentContainer = ""
    var postDeployment = ""
    var postDeploymentContainer = ""
    /// Whether a command needs to name the service it runs in: a Docker Compose application.
    var namesContainers = false
    /// Compose services Coolify knows by name, to pick from. Only those with a domain are known.
    var services: [String] = []
    /// The commands as Coolify returned them. A value is only checked once it is edited.
    private let loaded: DeploymentCommands

    init(application: Application) {
        self.init(
            commands: application.deploymentCommands ?? DeploymentCommands(),
            namesContainers: application.isDockerCompose,
            services: (application.dockerComposeDomains ?? [:]).keys
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    init(commands: DeploymentCommands, namesContainers: Bool = false, services: [String] = []) {
        loaded = commands
        self.namesContainers = namesContainers
        self.services = services
        preDeployment = commands.preDeployment ?? ""
        preDeploymentContainer = commands.preDeploymentContainer ?? ""
        postDeployment = commands.postDeployment ?? ""
        postDeploymentContainer = commands.postDeploymentContainer ?? ""
    }

    /// The commands as Coolify stores them, which trims them.
    var preValue: String { preDeployment.trimmingCharacters(in: .whitespacesAndNewlines) }
    var postValue: String { postDeployment.trimmingCharacters(in: .whitespacesAndNewlines) }
    var preContainerValue: String { preDeploymentContainer.trimmingCharacters(in: .whitespaces) }
    var postContainerValue: String { postDeploymentContainer.trimmingCharacters(in: .whitespaces) }

    /// A command set to run without naming its service, which only works while the app has a single container.
    var preNeedsContainer: Bool { namesContainers && !preValue.isEmpty && preContainerValue.isEmpty }
    var postNeedsContainer: Bool { namesContainers && !postValue.isEmpty && postContainerValue.isEmpty }

    /// What changed since `saved`. `nil` when nothing did.
    func changes(from saved: Self) -> DeploymentCommands? {
        var changes = DeploymentCommands()
        // An empty command clears it.
        if preValue != saved.preValue { changes.preDeployment = preValue }
        if postValue != saved.postValue { changes.postDeployment = postValue }
        // Coolify's API can't clear a name, so an emptied one stays out. `problem` says so when a command needs it.
        if namesContainers {
            if preContainerValue != saved.preContainerValue, !preContainerValue.isEmpty {
                changes.preDeploymentContainer = preContainerValue
            }
            if postContainerValue != saved.postContainerValue, !postContainerValue.isEmpty {
                changes.postDeploymentContainer = postContainerValue
            }
        }
        return changes.isEmpty ? nil : changes
    }

    /// The first value Coolify would refuse, by its own API rules. Only edited container names are checked. The
    /// commands themselves may be any shell, which Coolify allows on purpose.
    var problem: String? {
        guard namesContainers else { return nil }
        let original = Self(commands: loaded, namesContainers: namesContainers)
        for (command, name, before) in [
            (preValue, preContainerValue, original.preContainerValue),
            (postValue, postContainerValue, original.postContainerValue),
        ] where name != before {
            // Coolify validates the name as a string that is not nullable, and Laravel turns an empty one into null.
            // Without a command, the name does nothing, so it may stay as it is.
            if name.isEmpty {
                guard command.isEmpty else {
                    return "Coolify's API can't clear a service name. Name another service, or clear it in Coolify."
                }
                continue
            }
            if !DeploymentCommands.isContainerName(name) {
                return "A service name starts with a letter or digit, then letters, digits, and . _ - only."
            }
        }
        return nil
    }
}

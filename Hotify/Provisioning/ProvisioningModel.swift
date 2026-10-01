import CoolifyAPI
import Foundation

/// Takes a template to a running service: create it stopped, let the user set it up, then start it and watch.
///
/// Coolify creates first and asks second on purpose. It generates the passwords and addresses at creation, so the
/// setup step edits real values instead of guessing them from the compose file.
@Observable
final class ProvisioningModel {
    enum Stage: Hashable {
        case choosing
        case settingUp
        case starting
    }

    var stage: Stage = .choosing
    let placement: PlacementModel

    var name = ""
    var description = ""
    var isCreating = false
    var createProblem: ProvisioningProblem?

    private(set) var template: ServiceTemplate?
    private(set) var serviceUUID: String?
    /// The created service's name as Coolify stored it.
    var serviceName = ""
    var setup = SetupDraft()
    var isLoadingSetup = false
    var isSaving = false
    var isDiscarding = false
    var setupProblem: ProvisioningProblem?
    /// Set when the user chose to share a domain another resource already uses.
    private var overridesDomains = false

    var ignition = Ignition()

    private var client: CoolifyClient?

    init(placement: PlacementModel = PlacementModel()) {
        self.placement = placement
    }

    func prepare(_ client: CoolifyClient?, instanceID: UUID?) {
        self.client = client
        placement.prepare(client, instanceID: instanceID)
    }

    var instanceRoot: URL? {
        client.map { $0.apiBaseURL.deletingLastPathComponent().deletingLastPathComponent() }
    }

    var route: ResourceRoute? { serviceUUID.map(ResourceRoute.service) }

    var canCreate: Bool {
        client != nil && placement.placement.isComplete && !isCreating && !placement.isCreatingPlace
    }

    /// Creates the service, stopped, and moves on to setup.
    func create(_ template: ServiceTemplate) async {
        guard let client, canCreate,
            let serverUUID = placement.placement.serverUUID,
            let projectUUID = placement.placement.projectUUID,
            let environmentUUID = placement.placement.environmentUUID
        else { return }
        isCreating = true
        createProblem = nil
        defer { isCreating = false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let created = try await client.createService(
                ServiceDraft(
                    type: template.slug,
                    name: trimmedName.isEmpty ? template.slug : trimmedName,
                    description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                    serverUUID: serverUUID,
                    projectUUID: projectUUID,
                    environmentUUID: environmentUUID,
                    destinationUUID: placement.placement.destinationUUID
                )
            )
            self.template = template
            serviceUUID = created.uuid
            serviceName = trimmedName.isEmpty ? template.slug : trimmedName
            placement.remember()
            stage = .settingUp
            await loadSetup()
        } catch is CancellationError {
            return
        } catch {
            createProblem = ProvisioningProblem(error, template: template.slug)
        }
    }

    func loadSetup() async {
        guard let client, let serviceUUID, let template else { return }
        isLoadingSetup = true
        defer { isLoadingSetup = false }
        do {
            async let service = client.service(serviceUUID)
            async let variables = client.environmentVariables(of: .service(serviceUUID))
            let loadedService = try await service
            setup = SetupDraft(service: loadedService, variables: try await variables, outline: template.outline)
            serviceName = loadedService.name.isEmpty ? serviceName : loadedService.name
            setupProblem = nil
        } catch is CancellationError {
            return
        } catch {
            setupProblem = ProvisioningProblem(error)
        }
    }

    /// Saves the setup, starts the service, and moves on to watching it.
    func start() async {
        guard let client, let serviceUUID, await save() else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await client.startService(serviceUUID)
            ignition = Ignition()
            stage = .starting
        } catch {
            setupProblem = ProvisioningProblem(error)
        }
    }

    /// Repeats the start after the user chose to share a taken domain.
    func startSharingDomains() async {
        overridesDomains = true
        await start()
    }

    /// Saves what the user changed. Domains go first, because Coolify parses the compose file again after them.
    func save() async -> Bool {
        guard let client, let serviceUUID, !isSaving else { return false }
        isSaving = true
        setupProblem = nil
        defer { isSaving = false }
        do {
            let domains = setup.changedDomains
            if !domains.isEmpty {
                _ = try await client.updateService(
                    serviceUUID,
                    ServiceUpdate(urls: domains, forceDomainOverride: overridesDomains ? true : nil)
                )
                for index in setup.domains.indices {
                    setup.domains[index].original = setup.domains[index].trimmed
                }
            }
            let values = setup.changedValues
            if !values.isEmpty {
                _ = try await client.setEnvironmentVariables(values, on: .service(serviceUUID))
                for index in setup.settings.indices where !setup.settings[index].isHidden {
                    setup.settings[index].original = setup.settings[index].value
                }
            }
            return true
        } catch {
            setupProblem = ProvisioningProblem(error)
            return false
        }
    }

    /// Deletes the service that was just created, volumes and all. For backing out of setup.
    func discard() async -> Bool {
        guard let client, let serviceUUID else { return true }
        isDiscarding = true
        defer { isDiscarding = false }
        do {
            try await client.deleteService(serviceUUID)
            return true
        } catch {
            setupProblem = ProvisioningProblem(error)
            return false
        }
    }

    /// Polls the service until it runs. Keeps going after a stall, since a slow pull can still finish.
    func watch() async {
        guard let client, let serviceUUID else { return }
        while !Task.isCancelled, ignition.phase != .running {
            if let service = try? await client.service(serviceUUID) {
                ignition.observe(service)
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }
}

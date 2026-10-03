import CoolifyAPI
import Foundation

/// Takes an engine to a running database: create it with a start, then watch it come up.
///
/// A database needs no setup between creating and starting, unlike a service, so Coolify starts it at once.
@Observable
final class DatabaseProvisioningModel {
    let placement: PlacementModel

    var name = ""
    var description = ""
    /// An image with its tag. Empty takes Coolify's default for the engine.
    var image = ""
    var isPublic = false
    var publicPort: Int?
    private(set) var isCreating = false
    var createProblem: ProvisioningProblem?

    private(set) var engine: DatabaseEngine?
    /// Set once Coolify created the database. Its connection strings hold the password.
    private(set) var created: CreatedDatabase?
    var ignition = Ignition()

    private var client: CoolifyClient?

    init(placement: PlacementModel) {
        self.placement = placement
    }

    func prepare(_ client: CoolifyClient?) {
        self.client = client
    }

    var route: ResourceRoute? { created.map { .database($0.uuid) } }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (engine?.displayName ?? "Database") : trimmed
    }

    /// What Coolify would refuse, worded for the person filling the form.
    var problem: String? {
        if isPublic {
            guard let publicPort else { return "Public access needs a port." }
            if !(1...65_535).contains(publicPort) { return "A port is a number from 1 to 65535." }
        }
        let image = image.trimmingCharacters(in: .whitespaces)
        if !image.isEmpty, image.contains(" ") { return "An image has no spaces, such as postgres:17-alpine." }
        return nil
    }

    var canCreate: Bool {
        client != nil && placement.placement.isComplete && !isCreating && !placement.isCreatingPlace
            && !placement.isLoadingDestinations && problem == nil
    }

    /// Creates the database and starts it.
    func create(_ engine: DatabaseEngine) async {
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
        let trimmedImage = image.trimmingCharacters(in: .whitespaces)
        do {
            created = try await client.createDatabase(
                DatabaseDraft(
                    engine: engine,
                    name: trimmedName.isEmpty ? nil : trimmedName,
                    description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                    image: trimmedImage.isEmpty ? nil : trimmedImage,
                    serverUUID: serverUUID,
                    projectUUID: projectUUID,
                    environmentUUID: environmentUUID,
                    destinationUUID: placement.placement.destinationUUID,
                    isPublic: isPublic ? true : nil,
                    publicPort: isPublic ? publicPort : nil
                ))
            self.engine = engine
            placement.remember()
            ignition = Ignition()
        } catch is CancellationError {
            return
        } catch {
            createProblem = ProvisioningProblem(error)
        }
    }

    /// Polls the database until it runs. Keeps going after a stall, since a slow pull can still finish.
    func watch() async {
        guard let client, let uuid = created?.uuid else { return }
        while !Task.isCancelled, ignition.phase != .running {
            if let database = try? await client.database(uuid) {
                ignition.observe(database, name: displayName)
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }
}

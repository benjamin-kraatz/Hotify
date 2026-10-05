import CoolifyAPI
import Foundation

/// What to ask Coolify to do with one compose container.
enum ContainerCommand {
    case start
    case stop
    case restart
}

/// Loads each container's uuid, then starts, stops, or restarts one of them.
@Observable
final class ContainerActions {
    var lookupError: String?
    var actionError: String?
    private(set) var busyUUID: String?
    private var targets: [Target] = []

    var isBusy: Bool { busyUUID != nil }

    /// Fills an empty uuid when the list endpoints named the same container. Leaves the row alone otherwise.
    func resolved(_ containers: [ContainerSummary]) -> [ContainerSummary] {
        containers.map { container in
            guard container.uuid.isEmpty, let uuid = uuid(matching: container) else { return container }
            var copy = container
            copy.uuid = uuid
            return copy
        }
    }

    func isBusy(_ uuid: String) -> Bool {
        busyUUID == uuid
    }

    /// Drops uuids from the previous service. Does not touch the rows the dashboard already showed.
    func reset() {
        targets = []
        lookupError = nil
        actionError = nil
        busyUUID = nil
    }

    /// Reads both lists. The rows stay up while this runs; a failure only explains missing actions.
    func load(client: CoolifyClient, service serviceUUID: String) async {
        do {
            async let applications = client.serviceApplications(serviceUUID)
            async let databases = client.serviceDatabases(serviceUUID)
            let loadedApplications = try await applications
            let loadedDatabases = try await databases
            try Task.checkCancellation()
            targets =
                Self.targets(loadedApplications, isDatabase: false)
                + Self.targets(loadedDatabases, isDatabase: true)
            lookupError = nil
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            lookupError = (error as? CoolifyError)?.summary ?? error.localizedDescription
        }
    }

    func run(
        _ command: ContainerCommand,
        container: ContainerSummary,
        client: CoolifyClient,
        service serviceUUID: String
    ) async {
        let uuid = container.uuid
        guard !uuid.isEmpty, busyUUID == nil else { return }
        busyUUID = uuid
        actionError = nil
        defer { busyUUID = nil }
        let role: ServiceContainerRole = container.isDatabase ? .database : .application
        do {
            switch command {
            case .start:
                _ = try await client.startServiceContainer(serviceUUID, role: role, uuid: uuid)
            case .stop:
                _ = try await client.stopServiceContainer(serviceUUID, role: role, uuid: uuid)
            case .restart:
                _ = try await client.restartServiceContainer(serviceUUID, role: role, uuid: uuid)
            }
        } catch is CancellationError {
            return
        } catch {
            actionError = (error as? CoolifyError)?.summary ?? error.localizedDescription
        }
    }

    private func uuid(matching container: ContainerSummary) -> String? {
        let matches = targets.filter { $0.matches(container) }
        if matches.count == 1 { return matches[0].uuid }
        let listedID = Self.listedID(of: container)
        let sameID = matches.filter { listedID != 0 && $0.id == listedID }
        if sameID.count == 1 { return sameID[0].uuid }
        return nil
    }

    /// A database row stores `-id - 1`. Matching uses the id the list decoded.
    private static func listedID(of container: ContainerSummary) -> Int {
        guard container.isDatabase, container.id < 0 else { return container.id }
        return -container.id - 1
    }

    private static func targets(_ items: [ServiceApplication], isDatabase: Bool) -> [Target] {
        items.map {
            Target(name: $0.name, humanName: $0.humanName, id: $0.id, uuid: $0.uuid, isDatabase: isDatabase)
        }
    }
}

private struct Target: Hashable {
    var name: String
    var humanName: String?
    var id: Int
    var uuid: String
    var isDatabase: Bool

    /// The list's `name` is the compose service name. The row title may be `humanName` instead.
    func matches(_ container: ContainerSummary) -> Bool {
        guard isDatabase == container.isDatabase, !uuid.isEmpty else { return false }
        let wanted = [container.serviceName, container.name].filter { !$0.isEmpty }
        guard !wanted.isEmpty else { return false }
        if wanted.contains(name) { return true }
        if let humanName, wanted.contains(humanName) { return true }
        return false
    }
}

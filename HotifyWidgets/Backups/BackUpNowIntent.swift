import AppIntents
import CoolifyAPI
import WidgetKit

/// Runs a database's backup configuration once, from a widget. The schedule and retention stay as they are.
struct BackUpNowIntent: AppIntent {
    static let title: LocalizedStringResource = "Back Up Database Now"
    static let isDiscoverable = false

    @Parameter(title: "Database")
    var pinID: String

    @Parameter(title: "Backup")
    var backupUUID: String

    init() {}

    init(pin: ResourcePin, backupUUID: String) {
        pinID = pin.id
        self.backupUUID = backupUUID
    }

    func perform() async throws -> some IntentResult {
        guard let pin = ResourcePin(id: pinID), case .database(let database) = pin.route else { return .result() }
        var request = BackupRequest(at: .now)
        if case .success((_, let client)) = InstanceAccess.client(for: pin.instanceID) {
            do {
                _ = try await client.backUpNow(database: database, backup: backupUUID)
            } catch {
                request.failed = true
            }
        } else {
            request.failed = true
        }
        WidgetLedger.update { $0.backupRequests[pin.id] = request }
        return .result()
    }
}

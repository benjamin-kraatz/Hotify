import CoolifyAPI
import SwiftUI

/// Says Coolify cannot import into this database's engine, and which engines it can.
struct RestoreUnavailable: View {
    var target: RestoreTarget

    var body: some View {
        ContentUnavailableView {
            Label("No restore for \(target.engineName)", systemImage: "externaldrive.badge.xmark")
        } description: {
            Text(
                "Coolify imports backups into \(DatabaseImportEngine.supportedList) databases. "
                    + "\(target.name) runs \(target.engineName)."
            )
        }
    }
}

#Preview {
    RestoreUnavailable(
        target: RestoreTarget(
            importTarget: .database("db-1"), name: "cache", engine: nil, engineDescription: "Redis",
            status: "running:healthy")
    )
    .frame(width: 480, height: 320)
}

import CoolifyAPI
import SwiftUI

/// The engine's own restore switches, each only where Coolify reads it.
struct RestoreOptionsSection: View {
    @Binding var draft: RestoreDraft
    var engine: DatabaseImportEngine
    var format: BackupFormat

    var body: some View {
        Section {
            switch engine {
            case .postgresql: postgresql
            case .mysql, .mariadb: mysql
            case .mongodb: mongodb
            case .sqlite: sqlite
            }
        } header: {
            Text("Options")
        } footer: {
            if engine == .sqlite {
                Text(
                    "The file to replace. Left empty, Coolify uses the one the backup's name points to, or else the first."
                )
            }
        }
    }

    @ViewBuilder
    private var postgresql: some View {
        dumpAllToggle
        if !draft.dumpAll {
            Toggle(isOn: $draft.replaceExisting) {
                Text("Replace existing data")
                Text("Without it, an object that already exists stops the import, and nothing changes.")
            }
            if format != .sql {
                Toggle(isOn: $draft.keepOwners) {
                    Text("Keep owners and privileges")
                    Text("pg_dump archives only. The roles they name have to exist on this server.")
                }
            }
        }
    }

    @ViewBuilder
    private var mysql: some View {
        dumpAllToggle
        if draft.dumpAll {
            Toggle(isOn: $draft.restoreMySQLUsers) {
                Text("Also restore users and passwords")
                Text("Replaces the server's users. The credentials Coolify keeps can stop working.")
            }
        }
    }

    private var mongodb: some View {
        Toggle(isOn: $draft.replaceExisting) {
            Text("Drop collections before restoring")
            Text("Each collection in the backup replaces the one of the same name.")
        }
    }

    private var sqlite: some View {
        TextField("Database file", text: $draft.sqliteDatabase, prompt: Text("Chosen by Coolify"))
            .font(.body.monospaced())
            .autocorrectionDisabled()
            #if os(iOS)
        .textInputAutocapitalization(.never)
            #endif
    }

    private var dumpAllToggle: some View {
        Toggle(isOn: $draft.dumpAll) {
            Text("Backup contains all databases")
            Text("For a dump of the whole server. Every database on it is dropped first.")
        }
    }
}

#Preview {
    @Previewable @State var draft = RestoreDraft()
    Form {
        RestoreOptionsSection(draft: $draft, engine: .postgresql, format: .archive)
        RestoreOptionsSection(draft: $draft, engine: .mysql, format: .sql)
        RestoreOptionsSection(draft: $draft, engine: .sqlite, format: .unknown)
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 480)
}

import CoolifyAPI
import SwiftUI
import UniformTypeIdentifiers

/// Where the backup comes from: a file on this device, a stored backup run, or a path on the server.
struct RestoreSourceSection: View {
    @Binding var draft: RestoreDraft
    var kinds: [RestoreSourceKind]
    var runs: [RestorableRun]
    var engine: DatabaseImportEngine

    @State private var isPicking = false
    @State private var pickError: String?

    var body: some View {
        Section {
            if kinds.count > 1 {
                Picker("Source", selection: $draft.kind) {
                    ForEach(kinds) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
            }
            switch draft.kind {
            case .file: file
            case .run: run
            case .path: path
            }
        } header: {
            Text("Backup")
        } footer: {
            Text(footer)
        }
        .onChange(of: draft.runID) { _, _ in presetFromRun() }
    }

    @ViewBuilder
    private var file: some View {
        if let picked = draft.file {
            LabeledContent {
                Text(picked.sizeLabel)
                    .monospacedDigit()
            } label: {
                Label(picked.name, systemImage: "doc.zipper")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let problem = picked.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.glow)
            }
        }
        Button(draft.file == nil ? "Choose File…" : "Choose Another File…", systemImage: "folder") {
            isPicking = true
        }
        .fileImporter(isPresented: $isPicking, allowedContentTypes: [.item, .data]) { result in
            switch result {
            case .success(let url):
                do {
                    draft.file = try RestoreFile(url: url)
                    pickError = nil
                } catch {
                    pickError = "Hotify could not read \(url.lastPathComponent). \(error.localizedDescription)"
                }
            case .failure(let error):
                pickError = error.localizedDescription
            }
        }
        if let pickError {
            Label(pickError, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.glow)
        }
    }

    @ViewBuilder
    private var run: some View {
        Picker("Run", selection: $draft.runID) {
            Text("Choose a run").tag(String?.none)
            ForEach(runs) { run in
                Text(run.title).tag(Optional(run.id))
            }
        }
        if let chosen = draft.run(in: runs) {
            if let name = chosen.databaseName, !name.isEmpty {
                LabeledContent("Databases", value: name)
            }
            if let fileName = chosen.fileName {
                LabeledContent("File") {
                    Text(fileName)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            if chosen.sources.server != nil, chosen.sources.s3 != nil {
                Picker("Copy", selection: $draft.copy) {
                    Text("In S3").tag(StoredCopy.s3)
                    Text("On the server").tag(StoredCopy.server)
                }
            } else {
                LabeledContent("Copy", value: chosen.sources.s3 != nil ? "In S3" : "On the server")
            }
        }
    }

    private var path: some View {
        TextField("Path", text: $draft.path, prompt: Text(verbatim: "/data/coolify/backups/app.dmp"))
            .font(.body.monospaced())
            .autocorrectionDisabled()
            #if os(iOS)
        .textInputAutocapitalization(.never)
        .keyboardType(.URL)
            #endif
    }

    private var footer: String {
        switch draft.kind {
        case .file:
            let limit = ByteCountFormatter.string(fromByteCount: DatabaseImportFile.maxBytes, countStyle: .file)
            return "\(engine.acceptedFormats) Up to \(limit)."
        case .run:
            if let chosen = draft.run(in: runs), draft.storedSource(of: chosen) == chosen.sources.server {
                return "Importing from the server needs an API token with the deploy permission. "
                    + "The S3 copy works with a write token."
            }
            return "Coolify imports the run's dump from where it keeps it."
        case .path:
            return "An absolute path to a backup on the database's server. Importing from it needs an API token with "
                + "the deploy permission."
        }
    }

    /// A run of an all-databases schedule restores them all, and S3 works with a write token, so both start chosen.
    private func presetFromRun() {
        guard let chosen = draft.run(in: runs) else { return }
        draft.dumpAll = chosen.dumpAll
        draft.copy = chosen.sources.s3 != nil ? .s3 : .server
    }
}

#Preview {
    @Previewable @State var draft = RestoreDraft(
        kind: .file,
        file: RestoreFile(url: URL(filePath: "/tmp/app.dmp"), name: "app-2026-09-29.dmp", size: 48_211_302)
    )
    Form {
        RestoreSourceSection(draft: $draft, kinds: RestoreSourceKind.allCases, runs: [], engine: .postgresql)
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 320)
}

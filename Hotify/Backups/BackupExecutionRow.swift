import CoolifyAPI
import SwiftUI

/// An expandable execution with failure output and file information.
struct BackupExecutionRow: View {
    var execution: BackupExecution

    private var heat: Heat {
        switch execution.status {
        case "success", "finished": .lit
        case "failed", "error": .troubled
        case "running", "in_progress", "queued": .warming
        default: .unknown
        }
    }

    var body: some View {
        DisclosureGroup {
            if let message = execution.message, !message.isEmpty {
                Text(message).font(.callout.monospaced()).textSelection(.enabled)
            }
            if let filename = execution.filename { Text(filename).font(.caption).textSelection(.enabled) }
            if let size = execution.size {
                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
            }
        } label: {
            HStack {
                FlameGlyph(heat: heat, height: 16)
                Text(execution.status.capitalized)
                Spacer()
                if let date = execution.createdAtDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                }
            }
        }
    }
}

#Preview {
    let execution = try! JSONDecoder().decode(
        BackupExecution.self, from: Data(#"{"uuid":"example","status":"failed","message":"Storage unavailable"}"#.utf8))
    List { BackupExecutionRow(execution: execution) }
}

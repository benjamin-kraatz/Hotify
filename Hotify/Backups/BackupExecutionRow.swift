import CoolifyAPI
import SwiftUI

/// One backup run: how it went and when. Opens to show Coolify's message and the file it wrote.
struct BackupExecutionRow: View {
    var execution: BackupExecution
    @State private var isExpanded: Bool

    init(execution: BackupExecution, startsExpanded: Bool = false) {
        self.execution = execution
        _isExpanded = State(initialValue: startsExpanded)
    }

    private var message: String? {
        guard let message = execution.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty
        else { return nil }
        return message
    }

    private var hasDetail: Bool {
        message != nil || execution.filename != nil
    }

    /// The line under the status: why a failed run failed, and how much a good one wrote.
    private var summary: String? {
        execution.heat == .troubled ? message?.components(separatedBy: .newlines).first : execution.sizeLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                FlameGlyph(heat: execution.heat, height: 18)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(execution.statusLabel)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(execution.heat.needsAttention ? AnyShapeStyle(.glow) : AnyShapeStyle(.primary))
                    if let summary, !isExpanded {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                if let date = execution.createdAtDate {
                    Text(date, format: .relative(presentation: .named))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .help(date.formatted(date: .abbreviated, time: .standard))
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .opacity(hasDetail ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
            // The tap sits on this line only, so the text below stays selectable.
            .onTapGesture {
                guard hasDetail else { return }
                isExpanded.toggle()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(hasDetail ? .isButton : [])
            .accessibilityValue(hasDetail ? (isExpanded ? "Expanded" : "Collapsed") : "")

            if isExpanded {
                detail
                    .padding(.leading, 32)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .animation(.snappy, value: isExpanded)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message {
                Text(message)
                    .font(.caption.monospaced())
                    .foregroundStyle(execution.heat == .troubled ? AnyShapeStyle(.glow) : AnyShapeStyle(.primary))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let filename = execution.filename, !filename.isEmpty {
                Label(filename, systemImage: "doc.zipper")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let size = execution.sizeLabel {
                Label(size, systemImage: "internaldrive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    let executions = try! JSONDecoder().decode(
        [BackupExecution].self,
        from: Data(
            """
            [
                {"uuid": "b", "status": "failed", "message": "pg_dump: connection to server failed",
                 "createdAt": "2026-09-30T04:00:00Z"},
                {"uuid": "a", "status": "success", "filename": "/backups/pg-dump-app-1759118400.dmp",
                 "size": 48211302, "createdAt": "2026-09-29T04:00:00Z"}
            ]
            """.utf8))
    VStack(spacing: 0) {
        BackupExecutionRow(execution: executions[0], startsExpanded: true)
        Divider()
        BackupExecutionRow(execution: executions[1])
    }
    .well()
    .frame(width: 480)
    .padding()
}

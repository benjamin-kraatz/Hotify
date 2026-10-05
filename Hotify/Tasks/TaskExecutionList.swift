import CoolifyAPI
import SwiftUI

/// The runs of one scheduled task. Failed is glow, and a run still going is warming. Neither is red.
struct TaskExecutionList: View {
    var executions: [ScheduledTaskExecution]
    var isLoading: Bool
    var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Runs")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let error {
                NoticeBanner(message: error)
            }
            if isLoading, executions.isEmpty, error == nil {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if executions.isEmpty, error == nil {
                Text("This task has not run yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(executions.enumerated()), id: \.element.id) { index, execution in
                        if index > 0 {
                            Divider()
                                .padding(.leading, 32)
                        }
                        TaskExecutionRow(execution: execution)
                    }
                }
                .well(cornerRadius: 10)
            }
        }
    }
}

private struct TaskExecutionRow: View {
    var execution: ScheduledTaskExecution

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                FlameGlyph(heat: execution.heat, height: 16)
                    .frame(width: 16)
                Text(execution.statusLabel)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(execution.statusStyle)
                Spacer(minLength: 8)
                if let detail = execution.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let date = execution.startedAtDate ?? execution.createdAtDate {
                    Text(date, format: .relative(presentation: .named))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if let message = execution.messageText {
                Text(message)
                    .font(.caption.monospaced())
                    .foregroundStyle(execution.heat == .troubled ? AnyShapeStyle(.glow) : AnyShapeStyle(.primary))
                    .textSelection(.enabled)
                    .lineLimit(6)
                    .padding(.leading, 28)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

extension ScheduledTaskExecution {
    /// Success is lit, a failure needs a look, and a run still going is warming.
    var heat: Heat {
        switch status.lowercased() {
        case "success": .lit
        case "failed": .troubled
        case "running": .warming
        default: .unknown
        }
    }

    var statusLabel: String {
        switch status.lowercased() {
        case "success": "Succeeded"
        case "failed": "Failed"
        case "running": "Running"
        default: status.prefix(1).uppercased() + status.dropFirst()
        }
    }

    var statusStyle: AnyShapeStyle {
        switch heat {
        case .troubled, .warming: AnyShapeStyle(.glow)
        default: AnyShapeStyle(.primary)
        }
    }

    var messageText: String? {
        guard let message = message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else {
            return nil
        }
        return message
    }

    var detail: String? {
        var parts: [String] = []
        if let duration {
            if duration.rounded() == duration {
                parts.append("\(Int(duration))s")
            } else {
                parts.append(String(format: "%.1fs", duration))
            }
        }
        if retryCount > 0 {
            parts.append(retryCount == 1 ? "1 retry" : "\(retryCount) retries")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

#Preview {
    TaskExecutionList(
        executions: [
            ScheduledTaskExecution(
                uuid: "run-failed",
                status: "failed",
                message: "php: command not found",
                duration: 1.4,
                startedAt: "2026-10-05T12:00:00Z"
            ),
            ScheduledTaskExecution(
                uuid: "run-live",
                status: "running",
                startedAt: "2026-10-05T12:05:00Z"
            ),
            ScheduledTaskExecution(
                uuid: "run-ok",
                status: "success",
                message: "cache cleared",
                retryCount: 1,
                duration: 12,
                startedAt: "2026-10-04T12:00:00Z"
            ),
        ],
        isLoading: false,
        error: nil
    )
    .frame(width: 520)
    .padding()
}

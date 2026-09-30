import CoolifyAPI
import SwiftUI

/// One backup configuration: what it dumps and when, how its recent runs went, and the run history.
struct BackupCard: View {
    var backup: DatabaseBackup
    /// The database's name, for a configuration that names no databases of its own.
    var fallbackName: String
    /// When Hotify asked for a backup that Coolify has not listed yet.
    var pendingSince: Date?
    var isBusy: Bool
    var canRun: Bool
    var onRun: () -> Void

    private var history: [BackupExecution] { backup.history }

    /// Warming while a backup runs, then how the newest run went. Cold when nothing is scheduled and nothing ran.
    private var heat: Heat {
        if isBusy { return .warming }
        return history.first?.heat ?? (backup.enabled ? .unknown : .cold)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if history.count > 1 {
                BackupHistoryStrip(history: history)
            }
            runs
        }
        .animation(.snappy, value: history.map(\.id))
        .animation(.snappy, value: pendingSince)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            FlameGlyph(heat: heat, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(backup.databaseNames ?? fallbackName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Label(backup.scheduleLabel, systemImage: backup.enabled ? "clock" : "pause.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: onRun) {
                Label(isBusy ? "Backing Up…" : "Back Up Now", systemImage: "externaldrive.badge.plus")
            }
            // Plain glass. The header's lead action is the one prominent button on this screen.
            .glassButton()
            .disabled(!canRun || isBusy)
            .help("Run this backup once. Its schedule stays as it is.")
        }
    }

    private var runs: some View {
        VStack(spacing: 0) {
            if let pendingSince {
                PendingRow(since: pendingSince)
                    .transition(.move(edge: .top).combined(with: .opacity))
                if !history.isEmpty {
                    Divider()
                        .padding(.leading, 46)
                }
            }
            ForEach(Array(history.enumerated()), id: \.element.id) { index, execution in
                if index > 0 {
                    Divider()
                        .padding(.leading, 46)
                }
                // The newest run opens by itself when it failed. That message is what you came for.
                BackupExecutionRow(execution: execution, startsExpanded: index == 0 && execution.heat == .troubled)
            }
            if history.isEmpty, pendingSince == nil {
                Text(
                    backup.enabled
                        ? "No runs yet. The first one shows up here after the schedule fires, or back up now."
                        : "No runs yet. The schedule is off, so this only runs when you back up now."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        }
        .well()
    }
}

/// A backup Hotify asked for, until Coolify lists its execution.
private struct PendingRow: View {
    var since: Date

    var body: some View {
        HStack(spacing: 14) {
            FlameGlyph(heat: .warming, height: 18)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text("Requested")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.glow)
                Text("Its result shows up here once Coolify reports it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(since, style: .timer)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

/// One tick per recent run, oldest on the left, so a streak of failures shows before you read a row.
private struct BackupHistoryStrip: View {
    var history: [BackupExecution]

    private static let limit = 30

    /// Oldest first.
    private var recent: [BackupExecution] { history.prefix(Self.limit).reversed() }

    private var goodCount: Int { recent.count { $0.heat == .lit } }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 3) {
                ForEach(recent) { execution in
                    Capsule()
                        .fill(fill(for: execution.heat))
                        .frame(width: 5, height: 14)
                }
            }
            Text("\(goodCount) of the last \(recent.count) backed up")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }

    private func fill(for heat: Heat) -> AnyShapeStyle {
        switch heat {
        case .lit: AnyShapeStyle(.ember)
        case .warming, .troubled: AnyShapeStyle(.glow)
        case .cold, .unknown: AnyShapeStyle(.quaternary)
        }
    }
}

#Preview {
    let backups = try! JSONDecoder().decode(
        [DatabaseBackup].self,
        from: Data(
            """
            [
                {"uuid": "daily", "enabled": true, "frequency": "daily", "databasesToBackup": "app,analytics",
                 "executions": [
                    {"uuid": "1", "status": "success", "size": 48211302, "filename": "/backups/app-1.dmp",
                     "createdAt": "2026-09-27T04:00:00Z"},
                    {"uuid": "2", "status": "success", "size": 48300112, "filename": "/backups/app-2.dmp",
                     "createdAt": "2026-09-28T04:00:00Z"},
                    {"uuid": "3", "status": "success", "size": 48411702, "filename": "/backups/app-3.dmp",
                     "createdAt": "2026-09-29T04:00:00Z"},
                    {"uuid": "4", "status": "failed", "message": "S3 storage unavailable: connection timed out",
                     "createdAt": "2026-09-30T04:00:00Z"}
                 ]},
                {"uuid": "manual", "enabled": false, "executions": []}
            ]
            """.utf8))
    ScrollView {
        VStack(alignment: .leading, spacing: 28) {
            BackupCard(
                backup: backups[0], fallbackName: "postgres", pendingSince: nil, isBusy: false, canRun: true, onRun: {})
            BackupCard(
                backup: backups[1], fallbackName: "postgres", pendingSince: .now, isBusy: true, canRun: true, onRun: {})
        }
        .padding(20)
    }
    .frame(width: 560, height: 620)
}

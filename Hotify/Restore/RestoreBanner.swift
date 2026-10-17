import CoolifyAPI
import SwiftUI

/// A restore of this database that runs or just ended, at the top of its tab. Opens the restore sheet.
struct RestoreBanner: View {
    var job: RestoreJob
    var onOpen: () -> Void

    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: String {
        switch job.stage {
        case .uploading, .starting, .queued, .restoring: "Restoring \(job.target.name)"
        case .succeeded: "Restored \(job.target.name)"
        case .failed: "Restore of \(job.target.name) failed"
        case .uploadCancelled: "Restore of \(job.target.name) cancelled"
        case .lostTrack: "Lost track of the restore of \(job.target.name)"
        }
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                FlameGlyph(heat: job.stage.heat, height: 22)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(job.stage.heat.needsAttention ? AnyShapeStyle(.glow) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                    Text(job.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .contentTransition(.opacity)
                    if job.stage == .uploading {
                        ProgressView(value: job.fraction)
                            .tint(.ember)
                    }
                }
                Spacer(minLength: 8)
                Text(job.stage.isActive ? "Show" : "Details")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .well()
        .heatEdge(isActive: job.stage.isActive)
        .animation(reduceMotion ? nil : .snappy, value: job.stage)
        .help("Show this restore")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    let target = RestoreTarget(
        importTarget: .database("db-1"), name: "postgres", engine: .postgresql, status: "running:healthy")
    var uploading = RestoreJob(target: target, sourceLabel: "app.dmp", stage: .uploading)
    uploading.sentBytes = 120_000_000
    uploading.totalBytes = 480_000_000
    var failed = RestoreJob(target: target, sourceLabel: "app.dmp", stage: .failed)
    failed.coolifyStatus = "error"
    failed.exitCode = 1
    return VStack(spacing: 12) {
        RestoreBanner(job: uploading, onOpen: {})
        RestoreBanner(job: RestoreJob(target: target, sourceLabel: "app.dmp", stage: .succeeded), onOpen: {})
        RestoreBanner(job: failed, onOpen: {})
    }
    .padding(20)
    .frame(width: 520)
}

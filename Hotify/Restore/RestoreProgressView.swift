import CoolifyAPI
import SwiftUI

/// One restore as it runs: the upload, then the import's state with Coolify's output, and what to do once it ends.
struct RestoreProgressView: View {
    var job: RestoreJob
    var onCancelUpload: () -> Void
    var onCheckAgain: () -> Void
    var onNewRestore: () -> Void

    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                stageDetail
                if job.activityID != nil {
                    RestoreOutput(output: job.output, isFinished: !job.stage.isActive)
                }
                if !job.stage.isActive {
                    HStack {
                        Spacer()
                        Button("New Restore", systemImage: "arrow.counterclockwise", action: onNewRestore)
                            .glassButton()
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(reduceMotion ? nil : .snappy, value: job.stage)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            FlameGlyph(heat: job.stage.heat, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(job.stage.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(job.stage.heat.needsAttention ? AnyShapeStyle(.glow) : AnyShapeStyle(.primary))
                    .contentTransition(.opacity)
                Text("\(job.sourceLabel) into \(job.target.name)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if job.stage.isActive {
                Text(job.startedAt, style: .timer)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var stageDetail: some View {
        switch job.stage {
        case .uploading:
            upload
        case .starting, .queued, .restoring:
            note(
                "Coolify offers no way to stop an import once it has it. You can close this sheet. Hotify keeps "
                    + "following the import while it runs.")
        case .succeeded:
            NoticeBanner(
                message: "Coolify finished the import. Check that the app using \(job.target.name) works with the "
                    + "restored data.",
                tone: .done)
        case .failed:
            NoticeBanner(message: failure)
        case .uploadCancelled:
            note("Nothing was imported. Coolify removes the part it received on its own.")
        case .lostTrack:
            VStack(alignment: .leading, spacing: 10) {
                NoticeBanner(
                    message: job.problem
                        ?? "Hotify could not read the import's status. It may still be running in Coolify.",
                    systemImage: "questionmark.circle.fill")
                Button("Check Again", systemImage: "arrow.clockwise", action: onCheckAgain)
                    .glassButton()
            }
        }
    }

    private var upload: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: job.fraction)
                .tint(.ember)
            HStack {
                Text(
                    "\(bytes(job.sentBytes)) of \(bytes(job.totalBytes))"
                )
                .monospacedDigit()
                .contentTransition(.numericText())
                Spacer()
                Text(job.fraction, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            #if os(iOS)
            note(
                "Keep Hotify open until the upload finishes. iOS stops it soon after you switch away, which matters "
                    + "for a large backup.")
            #else
            note("You can close this sheet. The upload goes on while Hotify runs.")
            #endif
            HStack {
                Spacer()
                Button("Cancel Upload", systemImage: "xmark", role: .cancel, action: onCancelUpload)
                    .glassButton()
                    .help("Stop the upload. Nothing is imported.")
            }
        }
    }

    /// Coolify's own word for how it ended, its exit code, and the reason Hotify knows.
    private var failure: String {
        var parts: [String] = []
        if let status = job.coolifyStatus {
            let code = job.exitCode.map { ", exit code \($0)" } ?? ""
            parts.append("Coolify reported the import as \(status)\(code).")
        }
        if let problem = job.problem {
            parts.append(problem)
        }
        if parts.isEmpty {
            parts.append("The restore failed.")
        }
        return parts.joined(separator: " ")
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}

#Preview("Uploading") {
    var job = RestoreJob(target: restorePreviewTarget, sourceLabel: "app-2026-09-29.dmp", stage: .uploading)
    job.sentBytes = 1_200_000_000
    job.totalBytes = 3_400_000_000
    return RestoreProgressView(job: job, onCancelUpload: {}, onCheckAgain: {}, onNewRestore: {})
        .frame(width: 520, height: 420)
}

#Preview("Failed") {
    var job = RestoreJob(target: restorePreviewTarget, sourceLabel: "app-2026-09-29.dmp", stage: .failed)
    job.activityID = 42
    job.coolifyStatus = "error"
    job.exitCode = 1
    job.output = "pg_restore: error: relation \"users\" already exists\nNothing was changed."
    return RestoreProgressView(job: job, onCancelUpload: {}, onCheckAgain: {}, onNewRestore: {})
        .frame(width: 520, height: 520)
}

#Preview("Lost track") {
    var job = RestoreJob(target: restorePreviewTarget, sourceLabel: "app-2026-09-29.dmp", stage: .lostTrack)
    job.activityID = 42
    job.problem =
        "Hotify could not read the import's status (The request timed out.). The import may still be running in "
        + "Coolify, so check the database before you start another."
    return RestoreProgressView(job: job, onCancelUpload: {}, onCheckAgain: {}, onNewRestore: {})
        .frame(width: 520, height: 520)
}

private let restorePreviewTarget = RestoreTarget(
    importTarget: .database("db-1"), name: "postgres", engine: .postgresql, status: "running:healthy")

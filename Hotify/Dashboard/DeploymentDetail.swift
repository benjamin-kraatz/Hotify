import CoolifyAPI
import SwiftUI

/// One deployment: what shipped, how it went, and its build output. Refreshes while the build runs.
/// The screen that shows it supplies the way back, through `detailBack`.
struct DeploymentDetail: View {
    var client: CoolifyClient?
    var initial: DeploymentLine
    /// Asks Apple Intelligence what went wrong as soon as the output loads, as a notification's Explain does.
    var explainsOnLoad = false
    @State private var deployment: Deployment?
    @State private var didExplainOnLoad = false
    @State private var error: String?
    @State private var isLoading = false
    @State private var analyst = FailureAnalyst()
    @State private var spotlight: LogSpotlight?

    private var line: DeploymentLine {
        guard let deployment, let client else { return initial }
        return DeploymentLine(deployment: deployment, fallbackID: initial.id, clientAPIBaseURL: client.apiBaseURL)
    }

    /// The whole commit message once it loads. The timeline only carries the subject line.
    private var message: String? {
        let full = deployment?.commitMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        return full.flatMap { $0.isEmpty ? nil : $0 } ?? line.message
    }

    /// A failed build with output to read, on a device whose Apple Intelligence model is ready.
    private var canExplain: Bool {
        line.status == "failed" && deployment?.logs?.isEmpty == false && FailureAnalyst.isReady
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                DeploymentSummary(line: line, message: message)
                if let error {
                    NoticeBanner(message: error)
                }
                if canExplain {
                    FailureExplainer(analyst: analyst) {
                        analyst.explain(LogLine.parse(deployment?.logs ?? ""))
                    } onShowLine: { line in
                        spotlight = LogSpotlight(line: line.id)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 20)
            // The head takes what it needs first. The log gets the rest.
            .layoutPriority(1)

            if deployment != nil, deployment?.logs == nil {
                ContentUnavailableView(
                    "Build output unavailable",
                    systemImage: "text.alignleft",
                    description: Text(
                        "Coolify sent this deployment without its logs. Give the API token the read:sensitive permission to see them."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .well()
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            } else {
                LogView(
                    lines: LogLine.parse(deployment?.logs ?? ""),
                    rawLogs: deployment?.logs ?? "",
                    isLoading: isLoading,
                    lineCount: .constant(100),
                    showsLineCount: false,
                    spotlight: spotlight
                )
            }
        }
        .animation(.snappy, value: line)
        .animation(.snappy, value: error)
        .animation(.snappy, value: canExplain)
        .task(id: initial.id) { await followDeployment() }
        .onDisappear { analyst.reset() }
    }

    private func followDeployment() async {
        guard let client else { return }
        deployment = nil
        analyst.reset()
        spotlight = nil
        while !Task.isCancelled {
            isLoading = deployment == nil
            do {
                let loaded = try await client.deployment(initial.id)
                try Task.checkCancellation()
                deployment = loaded
                error = nil
                if explainsOnLoad, !didExplainOnLoad, canExplain {
                    didExplainOnLoad = true
                    analyst.explain(LogLine.parse(loaded.logs ?? ""))
                }
            } catch is CancellationError { return } catch {
                self.error = (error as? CoolifyError)?.message ?? error.localizedDescription
            }
            isLoading = false
            if let status = deployment?.status, !["queued", "in_progress"].contains(status) { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
        }
    }
}

/// The head of a deployment: a large flame, the commit message, then its status, commit, and timing.
private struct DeploymentSummary: View {
    var line: DeploymentLine
    var message: String?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            FlameGlyph(heat: line.heat, height: 38, tone: line.tone)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(message ?? line.statusLabel)
                    .font(.title3.weight(.semibold))
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                // One row when it fits. A phone wraps the timing to a second row instead of cutting it short.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        outcome
                        timing
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 14) { outcome }
                        HStack(spacing: 14) { timing }
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let url = line.url, let urlLabel = line.urlLabel {
                    Link(destination: url) {
                        Label(urlLabel, systemImage: "arrow.up.right")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var outcome: some View {
        HStack(spacing: 6) {
            progress
                .fontWeight(.semibold)
                .foregroundStyle(line.tone.tint(for: line.heat))
                .contentTransition(.interpolate)
            if let pullRequest = line.pullRequest {
                PullRequestBadge(number: pullRequest)
            }
            if line.isRestart {
                Chip(text: "Restart")
            }
            if line.isRollback {
                Chip(text: "Rollback")
            }
        }
        if let commit = line.commit {
            Text(commit)
                .font(.subheadline.monospaced())
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var timing: some View {
        if let startedAt = line.startedAt {
            Label(startedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
        }
        if let duration = line.duration {
            Label(
                duration.formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow)),
                systemImage: "timer"
            )
        }
    }

    /// The status. A running build counts up from when it started.
    private var progress: Text {
        if line.status == "in_progress", let startedAt = line.startedAt {
            return Text("Deploying for \(Text(startedAt, style: .timer).monospacedDigit())")
        }
        if line.status == "queued" {
            return Text("Waiting in the queue")
        }
        return Text(line.statusLabel)
    }
}

#Preview("Failed") {
    DeploymentDetail(
        client: nil,
        initial: DeploymentLine(
            id: "preview",
            status: "failed",
            commit: "77aa01e",
            message: "chore: bump node to 24",
            startedAt: .now.addingTimeInterval(-86_400),
            finishedAt: .now.addingTimeInterval(-86_380)
        )
    )
    .frame(width: 560, height: 480)
}

#Preview("Deploying") {
    DeploymentDetail(
        client: nil,
        initial: DeploymentLine(
            id: "preview",
            status: "in_progress",
            commit: "9f2c1ab",
            message: "feat: add a pricing page",
            pullRequest: 18,
            startedAt: .now.addingTimeInterval(-40),
            url: URL(string: "https://pr-18.example.com"),
            urlLabel: "pr-18.example.com"
        )
    )
    .frame(width: 560, height: 480)
}

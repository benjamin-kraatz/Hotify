import CoolifyAPI
import SwiftUI

/// A deployment's build output, refreshed while this detail remains visible.
struct DeploymentDetail: View {
    var client: CoolifyClient?
    var initial: DeploymentLine
    var onBack: () -> Void
    @State private var deployment: Deployment?
    @State private var error: String?
    @State private var isLoading = false

    private var line: DeploymentLine {
        guard let deployment, let client else { return initial }
        return DeploymentLine(deployment: deployment, fallbackID: initial.id, clientAPIBaseURL: client.apiBaseURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("All deployments", systemImage: "chevron.left", action: onBack)
            HStack {
                FlameGlyph(heat: line.heat, height: 20)
                Text(line.statusLabel).font(.headline)
                Spacer()
                if let duration = line.duration {
                    Text(duration.formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow)))
                }
            }
            if let message = deployment?.commitMessage ?? initial.message {
                Text(message).textSelection(.enabled)
            }
            if let commit = deployment?.commit ?? initial.commit {
                Text(commit).font(.caption.monospaced()).textSelection(.enabled)
            }
            if let started = line.startedAt {
                Text(started.formatted(date: .abbreviated, time: .standard)).font(.caption).foregroundStyle(.secondary)
            }
            if let error { NoticeBanner(message: error) }
            if deployment != nil, deployment?.logs == nil {
                ContentUnavailableView(
                    "Build output unavailable", systemImage: "text.alignleft",
                    description: Text("Coolify did not include logs. Your token may need read:sensitive permission."))
            } else {
                LogView(
                    lines: LogLine.parse(deployment?.logs ?? ""), rawLogs: deployment?.logs ?? "", isLoading: isLoading,
                    lineCount: .constant(100), showsLineCount: false)
            }
        }
        .padding(20)
        .task(id: initial.id) { await followDeployment() }
    }

    private func followDeployment() async {
        guard let client else { return }
        deployment = nil
        while !Task.isCancelled {
            isLoading = deployment == nil
            do {
                let loaded = try await client.deployment(initial.id)
                try Task.checkCancellation()
                deployment = loaded
                error = nil
            } catch is CancellationError { return } catch {
                self.error = (error as? CoolifyError)?.message ?? error.localizedDescription
            }
            isLoading = false
            if let status = deployment?.status, !["queued", "in_progress"].contains(status) { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
        }
    }

}

#Preview {
    DeploymentDetail(
        client: nil, initial: DeploymentLine(id: "preview", status: "failed", message: "Build failed"), onBack: {})
}

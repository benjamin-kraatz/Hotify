import CoolifyAPI
import Foundation

/// The runtime output of one preview's containers.
@MainActor @Observable
final class PreviewLogModel {
    var logs = "" {
        didSet { lines = LogLine.parse(logs) }
    }
    private(set) var lines: [LogLine] = []
    var lineCount = 100
    var error: String?
    var isLoading = false

    /// Polls the log until the task is cancelled.
    func follow(client: CoolifyClient, application: String, number: Int) async {
        logs = ""
        error = nil
        while !Task.isCancelled {
            isLoading = logs.isEmpty
            do {
                let loaded = try await client.previewLogs(
                    applicationUUID: application, pullRequestID: number, window: .lines(lineCount),
                    showTimestamps: true)
                try Task.checkCancellation()
                logs = loaded
                error = nil
            } catch is CancellationError {
                return
            } catch {
                self.error = (error as? CoolifyError)?.message ?? error.localizedDescription
            }
            isLoading = false
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
        }
    }
}

import Foundation
import FoundationModels
import SwiftUI

/// Asks the on-device Apple Intelligence model why a deployment failed. The log never leaves the device.
@Observable
final class FailureAnalyst {
    enum Phase: Hashable {
        case idle
        /// The model has the log and has not written anything yet.
        case reading
        case writing(FailureInsight)
        case done(FailureInsight)
        case failed(String)
    }

    private(set) var phase = Phase.idle
    private var task: Task<Void, Never>?

    /// Whether the model can answer right now. False on iOS 18, on a device without Apple Intelligence,
    /// while Apple Intelligence is switched off, and while the model still downloads.
    static var isReady: Bool {
        guard #available(iOS 26, *) else { return false }
        return SystemLanguageModel.default.availability == .available
    }

    func explain(_ lines: [LogLine]) {
        guard #available(iOS 26, *) else { return }
        task?.cancel()
        phase = .reading
        task = Task { await run(lines) }
    }

    /// Stops a running analysis and forgets the last one.
    func reset() {
        task?.cancel()
        task = nil
        phase = .idle
    }

    @available(iOS 26, *)
    private func run(_ lines: [LogLine]) async {
        // The reserve covers the instructions, the answer's schema, and the answer. Build output runs to about
        // 2.4 characters a token, so two characters a token leaves headroom. The cap keeps the wait short.
        var budget = min(max(SystemLanguageModel.default.contextSize - 1_200, 800) * 2, 12_000)
        for attempt in 0..<2 {
            do {
                try await write(FailureDigest(lines: lines, budget: budget))
                return
            } catch {
                // A cancelled stream does not always throw `CancellationError`.
                if Task.isCancelled { return }
                if attempt == 0, Self.isOverflow(error) {
                    budget /= 2
                    continue
                }
                show(.failed(Self.message(for: error)))
                return
            }
        }
    }

    @available(iOS 26, *)
    private func write(_ digest: FailureDigest) async throws {
        let session = LanguageModelSession(instructions: Self.instructions)
        // Greedy, so the same log gets the same explanation every time.
        let stream = session.streamResponse(
            to: digest.prompt,
            generating: FailureDraft.self,
            options: GenerationOptions(samplingMode: .greedy)
        )
        var insight = FailureInsight()
        for try await snapshot in stream {
            try Task.checkCancellation()
            insight = FailureInsight(draft: snapshot.content, digest: digest)
            if !insight.isEmpty {
                show(.writing(insight))
            }
        }
        try Task.checkCancellation()
        show(insight.isEmpty ? .failed("Apple Intelligence found nothing to say about this output.") : .done(insight))
    }

    /// Animated from here, so the card and the log below it move together as the answer grows.
    private func show(_ next: Phase) {
        withAnimation(.smooth) {
            phase = next
        }
    }

    private static let instructions = """
        You explain failed deployments to a developer. The deployment ran on Coolify, a self-hosted platform \
        that builds an application into a Docker image and starts it as a container. Environment variables are \
        set in Coolify, not in the repository. You get lines from the build output. Find the most likely cause \
        of the failure and rely only on what the lines say. Skip lines that only report that the deployment \
        failed and point to the first line that shows why. If the lines do not show a cause, say that plainly \
        and do not guess.
        """

    /// macOS and iOS 27 moved these errors to `LanguageModelError`. Version 26 throws `GenerationError`.
    @available(iOS 26, *)
    private static func isOverflow(_ error: Error) -> Bool {
        if #available(iOS 27, macOS 27, *), case LanguageModelError.contextSizeExceeded = error { return true }
        if case LanguageModelSession.GenerationError.exceededContextWindowSize = error { return true }
        return false
    }

    @available(iOS 26, *)
    private static func isRefusal(_ error: Error) -> Bool {
        if #available(iOS 27, macOS 27, *) {
            if case LanguageModelError.guardrailViolation = error { return true }
            if case LanguageModelError.refusal = error { return true }
        }
        if case LanguageModelSession.GenerationError.guardrailViolation = error { return true }
        if case LanguageModelSession.GenerationError.refusal = error { return true }
        return false
    }

    @available(iOS 26, *)
    private static func message(for error: Error) -> String {
        if isRefusal(error) {
            return "Apple Intelligence declined to read this output. The log below still has the whole story."
        }
        return "Apple Intelligence could not explain this failure just now."
    }
}

/// The shape the model fills in. It writes the properties in this order, so the headline arrives first.
@available(iOS 26, *)
@Generable
nonisolated struct FailureDraft {
    @Guide(description: "The most likely cause of the failure, as one short sentence")
    var headline: String
    @Guide(
        description:
            "Two or three plain sentences on what went wrong, naming the file, command, or package involved"
    )
    var explanation: String
    // Quotes, because the model copies text far more reliably than it counts lines.
    @Guide(
        description: "The error messages that show the cause, each copied word for word from one line",
        .maximumCount(3)
    )
    var evidence: [String]
    @Guide(description: "Concrete things to try next, each one short sentence", .maximumCount(3))
    var steps: [String]
}

extension FailureInsight {
    @available(iOS 26, *)
    fileprivate init(draft: FailureDraft.PartiallyGenerated, digest: FailureDigest) {
        headline = draft.headline ?? ""
        explanation = draft.explanation ?? ""
        steps = draft.steps ?? []
        // Until the steps begin, the last quote may still be half written.
        let quotes = draft.steps == nil ? (draft.evidence ?? []).dropLast() : (draft.evidence ?? [])[...]
        for quote in quotes {
            if let line = digest.line(quoting: quote), !evidence.contains(line) {
                evidence.append(line)
            }
        }
    }
}

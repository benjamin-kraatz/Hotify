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

    /// The most snapshots the card waits through before it updates. It updates sooner when a sentence ends,
    /// so this only paces a long sentence. One shows every snapshot as it arrives.
    static let snapshotsPerUpdate = 20

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
        var shown = FailureInsight()
        var held = 0
        for try await snapshot in stream {
            try Task.checkCancellation()
            insight = FailureInsight(draft: snapshot.content, digest: digest)
            held += 1
            // The model sends a snapshot every word or so. The card takes them a sentence at a time.
            guard !insight.isEmpty, held >= Self.snapshotsPerUpdate || insight.isWorthShowing(after: shown) else {
                continue
            }
            show(.writing(insight.withoutUnfinishedStep))
            shown = insight
            held = 0
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
    /// Without the last step while the model is still in the middle of it, so no step shows half written.
    fileprivate var withoutUnfinishedStep: FailureInsight {
        guard let last = steps.last?.last, !".!?".contains(last) else { return self }
        var settled = self
        settled.steps.removeLast()
        return settled
    }

    /// A sentence ended, or a quoted line or a step joined since `shown`.
    fileprivate func isWorthShowing(after shown: FailureInsight) -> Bool {
        if evidence.count != shown.evidence.count || steps.count != shown.steps.count { return true }
        // The headline is done once the explanation begins.
        if explanation.isEmpty != shown.explanation.isEmpty { return true }
        guard self != shown, let last = (steps.last ?? explanation).last else { return false }
        return ".!?".contains(last)
    }

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

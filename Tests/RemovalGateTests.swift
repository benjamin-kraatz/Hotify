// Checks that a delete goes out only after a fresh owner confirmation for its own target. No prompt, no network:
//
//     swiftc -parse-as-library Hotify/Removal/OwnerConfirmation.swift Hotify/Removal/RemovalGate.swift \
//         Tests/RemovalGateTests.swift -o "$TMPDIR/hotify-removal-gate-tests" && "$TMPDIR/hotify-removal-gate-tests"

import Foundation

/// Stands in for Face ID, Touch ID, or the passcode. Each prompt waits until the test answers it.
@MainActor
final class ScriptedConfirmer: OwnerConfirming {
    private(set) var reasons: [String] = []
    private(set) var cancels = 0
    private var prompts: [CheckedContinuation<OwnerConfirmation, Never>?] = []

    var asked: Int { reasons.count }

    func confirmOwner(reason: String) async -> OwnerConfirmation {
        reasons.append(reason)
        return await withCheckedContinuation { prompts.append($0) }
    }

    func cancel() {
        cancels += 1
    }

    /// Answers the `index`th prompt, counting from the first.
    func answer(_ index: Int, _ answer: OwnerConfirmation) {
        prompts[index]?.resume(returning: answer)
        prompts[index] = nil
    }
}

/// Stands in for the transport. Records every target handed to it.
@MainActor
final class Transport {
    var sent: [String] = []
    var failure: (any Error)?
    private var held: CheckedContinuation<Void, Never>?
    var holds = false

    func send(_ target: String) async throws {
        sent.append(target)
        if holds {
            await withCheckedContinuation { held = $0 }
        }
        if let failure { throw failure }
    }

    func release() {
        held?.resume()
        held = nil
    }
}

@MainActor
final class OutcomeBox {
    var outcome: RemovalGate<String>.Outcome?
}

struct Refused: LocalizedError {
    var errorDescription: String? { "The environment still has resources." }
}

@main
@MainActor
struct RemovalGateTests {
    static var failures = 0

    static func main() async {
        await confirmedSendsExactlyTheTarget()
        await unconfirmedSendsNothing()
        await earlierConfirmationDoesNotCarryOver()
        await secondTapWhileAskingIsRefused()
        await secondTapWhileSendingIsRefused()
        await cancelWhileAskingSendsNothing()
        await newTargetWithdrawsTheOldOne()
        await refusedRequestKeepsTheGateUsable()
        if failures > 0 {
            print("\(failures) removal gate check(s) failed")
            exit(1)
        }
        print("Removal gate checks passed")
    }

    static func confirmedSendsExactlyTheTarget() async {
        let (gate, confirmer, transport) = make()
        let removal = start(gate, "app-1", transport)
        await settle { confirmer.asked == 1 }
        check(gate.phase == .confirming("app-1"), "asks before it sends")
        check(transport.sent.isEmpty, "nothing goes out while the owner is asked")
        confirmer.answer(0, .confirmed)
        check(await removal.value == .removed, "a confirmed delete reports removed")
        check(transport.sent == ["app-1"], "a confirmed delete sends its own target once")
        check(confirmer.reasons == ["delete app-1"], "the prompt names the target")
        check(gate.phase == .idle && gate.problem == nil, "the gate is idle again")
    }

    static func unconfirmedSendsNothing() async {
        let answers: [(OwnerConfirmation, RemovalGate<String>.Problem)] = [
            (.cancelled, .cancelled),
            (.unavailable, .unavailable),
            (.failed("Too many attempts."), .notConfirmed("Too many attempts.")),
        ]
        for (answer, problem) in answers {
            let (gate, confirmer, transport) = make()
            let removal = start(gate, "db-1", transport)
            await settle { confirmer.asked == 1 }
            confirmer.answer(0, answer)
            check(await removal.value == .notConfirmed(answer), "\(answer) is reported")
            check(transport.sent.isEmpty, "\(answer) sends nothing")
            check(gate.problem == problem, "\(answer) leaves a problem to show")
            check(gate.phase == .idle, "\(answer) lets the owner try again")
        }
    }

    static func earlierConfirmationDoesNotCarryOver() async {
        let (gate, confirmer, transport) = make()
        let first = start(gate, "svc-1", transport)
        await settle { confirmer.asked == 1 }
        confirmer.answer(0, .confirmed)
        _ = await first.value
        let second = start(gate, "svc-2", transport)
        await settle { confirmer.asked == 2 }
        check(transport.sent == ["svc-1"], "the second delete waits for its own confirmation")
        confirmer.answer(1, .cancelled)
        check(await second.value == .notConfirmed(.cancelled), "a refusal after an approval holds")
        check(transport.sent == ["svc-1"], "an earlier approval does not send the next delete")
    }

    static func secondTapWhileAskingIsRefused() async {
        let (gate, confirmer, transport) = make()
        let first = start(gate, "app-1", transport)
        await settle { confirmer.asked == 1 }
        check(await settled(start(gate, "app-1", transport)) == .busy, "a second tap waits")
        check(await settled(start(gate, "app-2", transport)) == .busy, "so does another target")
        check(confirmer.asked == 1, "the owner is asked once")
        confirmer.answer(0, .confirmed)
        _ = await first.value
        check(transport.sent == ["app-1"], "one confirmation sends one request")
    }

    static func secondTapWhileSendingIsRefused() async {
        let (gate, confirmer, transport) = make()
        transport.holds = true
        let first = start(gate, "app-1", transport)
        await settle { confirmer.asked == 1 }
        confirmer.answer(0, .confirmed)
        await settle { transport.sent.count == 1 }
        check(gate.isRemoving, "the gate says the request is out")
        check(await settled(start(gate, "app-1", transport)) == .busy, "a tap mid-request waits")
        gate.cancel()
        check(gate.isRemoving, "a request already sent is not withdrawn")
        transport.release()
        check(await first.value == .removed, "the request finishes")
        check(transport.sent == ["app-1"] && confirmer.asked == 1, "no second request or prompt")
    }

    static func cancelWhileAskingSendsNothing() async {
        let (gate, confirmer, transport) = make()
        let removal = start(gate, "proj-1", transport)
        await settle { confirmer.asked == 1 }
        gate.cancel()
        check(confirmer.cancels == 1, "cancelling ends the prompt")
        check(gate.phase == .idle, "cancelling frees the gate")
        // The prompt answers late, as a fingerprint already on the sensor would.
        confirmer.answer(0, .confirmed)
        check(await removal.value == .withdrawn, "a late confirmation is withdrawn")
        check(transport.sent.isEmpty, "a dismissed delete sends nothing")
    }

    static func newTargetWithdrawsTheOldOne() async {
        let (gate, confirmer, transport) = make()
        let old = start(gate, "env-staging", transport)
        await settle { confirmer.asked == 1 }
        // What a view does when the resource on screen changes under the dialog.
        gate.cancel()
        let new = start(gate, "env-preview", transport)
        await settle { confirmer.asked == 2 }
        confirmer.answer(0, .confirmed)
        check(await old.value == .withdrawn, "the old target's confirmation is spent on nothing")
        check(transport.sent.isEmpty, "the old confirmation does not send the new target")
        check(gate.phase == .confirming("env-preview"), "the new delete still waits for its own answer")
        confirmer.answer(1, .confirmed)
        check(await new.value == .removed, "the new delete goes through on its own confirmation")
        check(transport.sent == ["env-preview"], "only the new target is sent")
    }

    static func refusedRequestKeepsTheGateUsable() async {
        let (gate, confirmer, transport) = make()
        transport.failure = Refused()
        let first = start(gate, "env-1", transport)
        await settle { confirmer.asked == 1 }
        confirmer.answer(0, .confirmed)
        check(await first.value == .failed, "a refused request reports failed")
        check(gate.problem == .refused("The environment still has resources."), "Coolify's words are kept")
        transport.failure = nil
        let retry = start(gate, "env-1", transport)
        await settle { confirmer.asked == 2 }
        check(gate.problem == nil, "a retry clears the old problem")
        confirmer.answer(1, .confirmed)
        check(await retry.value == .removed, "a retry asks again and goes through")
        check(transport.sent == ["env-1", "env-1"], "each try sent once")
    }

    // MARK: Helpers

    static func make() -> (RemovalGate<String>, ScriptedConfirmer, Transport) {
        let confirmer = ScriptedConfirmer()
        return (RemovalGate<String>(confirmer: confirmer), confirmer, Transport())
    }

    static func start(_ gate: RemovalGate<String>, _ target: String, _ transport: Transport)
        -> Task<RemovalGate<String>.Outcome, Never>
    {
        Task { await gate.remove(target, reason: "delete \(target)", send: transport.send) }
    }

    /// The outcome of a delete that should end without a prompt, or `nil` if it is still waiting on one.
    static func settled(_ removal: Task<RemovalGate<String>.Outcome, Never>) async -> RemovalGate<String>.Outcome? {
        let box = OutcomeBox()
        Task { box.outcome = await removal.value }
        await settle { box.outcome != nil }
        return box.outcome
    }

    /// Lets the tasks run until `condition` holds.
    static func settle(_ condition: () -> Bool) async {
        for _ in 0..<1_000 where !condition() {
            await Task.yield()
        }
        check(condition(), "timed out waiting")
    }

    static func check(_ condition: Bool, _ message: String, line: Int = #line) {
        guard !condition else { return }
        failures += 1
        print("FAIL line \(line): \(message)")
    }
}

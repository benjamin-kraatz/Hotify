import Foundation

/// What the on-device model made of a failed deployment. The fields fill in as the model writes.
struct FailureInsight: Hashable {
    var headline = ""
    var explanation = ""
    /// The log lines the model points to as the cause.
    var evidence: [LogLine] = []
    var steps: [String] = []

    var isEmpty: Bool {
        headline.isEmpty && explanation.isEmpty
    }
}

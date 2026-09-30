import SwiftUI

/// Why a deployment failed: the cause, the log lines behind it, and what to try. Fills in as the model writes.
struct FailureInsightCard: View {
    var phase: FailureAnalyst.Phase
    var onShowLine: (LogLine) -> Void = { _ in }
    var onRetry: () -> Void = {}
    var onClose: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isWorking: Bool {
        switch phase {
        case .idle, .reading, .writing: true
        case .done, .failed: false
        }
    }

    private var insight: FailureInsight? {
        switch phase {
        case .writing(let insight), .done(let insight): insight
        case .idle, .reading, .failed: nil
        }
    }

    private var title: String {
        if let insight {
            return insight.headline.isEmpty ? "Reading the build output…" : insight.headline
        }
        if case .failed = phase {
            return "No explanation"
        }
        return "Reading the build output…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            // The log below keeps its room. A long explanation scrolls inside the card instead.
            HeightCap(height: 300) {
                ViewThatFits(in: .vertical) {
                    details
                    ScrollView { details }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .well()
        // A row fading in while the card grows would otherwise draw past its edge.
        .clipShape(.rect(cornerRadius: 14))
        .heatEdge(isActive: isWorking)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "apple.intelligence")
                .foregroundStyle(.glow)
                .symbolEffect(.breathe, isActive: isWorking)
                .accessibilityHidden(true)
            Text(Self.inline(title))
                .font(.headline)
                .foregroundStyle(insight?.headline.isEmpty == false ? .primary : .secondary)
                .contentTransition(.interpolate)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button("Close", systemImage: "xmark", action: onClose)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(isWorking ? "Stop and hide the explanation" : "Hide the explanation")
        }
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            if case .failed(let message) = phase {
                Text(message)
                    .font(.callout)
                Button("Try Again", systemImage: "arrow.clockwise", action: onRetry)
                    .glassButton()
            } else if let insight, !insight.explanation.isEmpty {
                written(insight)
            } else {
                placeholder
            }
        }
        // As tall as the stand-in lines while the model writes, so the first sentence does not shrink the card.
        .frame(maxWidth: .infinity, minHeight: isWorking ? 49 : nil, alignment: .topLeading)
    }

    @ViewBuilder
    private func written(_ insight: FailureInsight) -> some View {
        Text(Self.inline(insight.explanation))
            .font(.callout)
            .contentTransition(.interpolate)
            .textSelection(.enabled)

        if !insight.evidence.isEmpty {
            VStack(spacing: 4) {
                ForEach(insight.evidence) { line in
                    EvidenceRow(line: line) { onShowLine(line) }
                        .transition(.opacity)
                }
            }
        }

        if !insight.steps.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("Try next")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(insight.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1)")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(.glow)
                        Text(Self.inline(step))
                            .contentTransition(.interpolate)
                            .textSelection(.enabled)
                    }
                    .font(.callout)
                    .transition(.opacity)
                }
            }
            .transition(.opacity)
        }

        if case .done = phase {
            Text("Written on this device by Apple Intelligence. It can be wrong, so check it against the output.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .transition(.opacity)
        }
    }

    /// Stand-in lines for the explanation, until the model starts to write.
    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach([1, 0.9, 0.55], id: \.self) { width in
                Capsule()
                    .fill(.quaternary)
                    .frame(height: 9)
                    .scaleEffect(x: width, anchor: .leading)
            }
        }
        .phaseAnimator(reduceMotion ? [1] : [0.45, 1]) { bars, opacity in
            bars.opacity(opacity)
        } animation: { _ in
            .easeInOut(duration: 0.9)
        }
        .padding(.vertical, 3)
        .accessibilityHidden(true)
    }

    /// The model wraps file names and commands in backticks. Rendered as inline Markdown, they turn to code.
    private static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// One log line the model cites. Jumps to the line in the build output.
private struct EvidenceRow: View {
    var line: LogLine
    var onShow: () -> Void

    var body: some View {
        Button(action: onShow) {
            HStack(spacing: 8) {
                Text(line.text.trimmingCharacters(in: .whitespaces))
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.down")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.glow)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.glow.opacity(0.12), in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("Show this line in the build output")
        .accessibilityHint("Shows this line in the build output")
    }
}

/// Offers its content at most `height`, and takes only what the content uses.
private struct HeightCap: Layout {
    var height: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let capped = ProposedViewSize(width: proposal.width, height: min(proposal.height ?? height, height))
        return subviews.first?.sizeThatFits(capped) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

#Preview("Reading") {
    FailureInsightCard(phase: .reading)
        .padding(20)
        .frame(width: 520)
}

#Preview("Done") {
    FailureInsightCard(
        phase: .done(
            FailureInsight(
                headline: "A type error stopped the Next.js build",
                explanation:
                    "`next build` failed while checking types. `src/app/checkout/page.tsx` reads `cart.currency`, and the `Cart` type has no such property.",
                evidence: [
                    LogLine(
                        id: 27,
                        text: "#12 27.81 Type error: Property 'currency' does not exist on type 'Cart'.",
                        isAlarming: true
                    ),
                    LogLine(id: 26, text: "#12 27.81 ./src/app/checkout/page.tsx:42:27", isAlarming: false),
                ],
                steps: [
                    "Add `currency` to the `Cart` type, or stop passing it to `Total`.",
                    "Run `npm run build` locally before you push.",
                ]
            )
        )
    )
    .padding(20)
    .frame(width: 520)
}

#Preview("Failed") {
    FailureInsightCard(phase: .failed("Apple Intelligence could not explain this failure just now."))
        .padding(20)
        .frame(width: 520)
}

import SwiftUI

/// The way into a failed deployment's explanation: a button first, then the card it unfolds into.
struct FailureExplainer: View {
    var analyst: FailureAnalyst
    var onExplain: () -> Void
    var onShowLine: (LogLine) -> Void

    @State private var isOpen = false

    private var isWorking: Bool {
        switch analyst.phase {
        case .reading, .writing: true
        case .idle, .done, .failed: false
        }
    }

    /// The card grows out of the button's corner and shrinks back into it.
    private static let swap = AnyTransition.scale(scale: 0.4, anchor: .topLeading).combined(with: .opacity)

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isOpen {
                FailureInsightCard(phase: analyst.phase, onShowLine: onShowLine, onRetry: onExplain, onClose: close)
                    .transition(Self.swap)
            } else {
                Button(action: open) {
                    Label {
                        Text("Explain Failure")
                    } icon: {
                        Image(systemName: "apple.intelligence")
                            .foregroundStyle(.glow)
                    }
                }
                .glassButton()
                .help("Ask Apple Intelligence what went wrong. The output stays on this device.")
                .transition(Self.swap)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // An analysis started elsewhere, such as from a notification's Explain, opens the card too.
        .onAppear { if analyst.phase != .idle { isOpen = true } }
        .onChange(of: analyst.phase) { before, phase in
            if before == .idle, phase != .idle, !isOpen {
                withAnimation(.snappy) { isOpen = true }
            }
        }
        .sensoryFeedback(trigger: analyst.phase) { _, phase in
            switch phase {
            case .done: .success
            case .failed: .warning
            case .idle, .reading, .writing: nil
            }
        }
    }

    /// Asks the model once. Opening the card again shows the explanation it already wrote.
    private func open() {
        if analyst.phase == .idle {
            onExplain()
        }
        // Animated from here, so the log below moves with the card.
        withAnimation(.snappy) {
            isOpen = true
        }
    }

    private func close() {
        withAnimation(.snappy) {
            isOpen = false
        }
        if isWorking {
            analyst.reset()
        }
    }
}

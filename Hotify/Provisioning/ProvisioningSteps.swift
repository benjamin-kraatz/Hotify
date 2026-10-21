import SwiftUI

/// The steps from choosing to running. Choosing and placing are one screen, so a resource is created in the first step.
/// A database or an application skips setup.
enum ProvisioningStep: Int, CaseIterable, Identifiable {
    case create
    case setUp
    case start

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .create: "Create"
        case .setUp: "Set Up"
        case .start: "Start"
        }
    }

    /// The steps for a resource Coolify can start as it creates it, which needs no setup.
    static let instant: [ProvisioningStep] = [.create, .start]
}

/// Where the user is in provisioning, as a row of small flames: lit behind, flickering here, cold ahead.
struct ProvisioningSteps: View {
    var current: ProvisioningStep
    /// The last step finished, which lights its own flame too.
    var isFinished = false
    var steps: [ProvisioningStep] = ProvisioningStep.allCases

    @SwiftUI.Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        HStack(spacing: 6) {
            ForEach(steps) { step in
                if step != steps.first {
                    Capsule()
                        .fill(
                            step.rawValue <= current.rawValue
                                ? AnyShapeStyle(.ember.opacity(0.6)) : AnyShapeStyle(.quaternary)
                        )
                        .frame(width: 14, height: 2)
                }
                HStack(spacing: 5) {
                    FlameGlyph(heat: heat(for: step), height: 13)
                    if sizeClass != .compact || step == current {
                        Text(step.title)
                            .font(.caption.weight(step == current ? .semibold : .regular))
                            .foregroundStyle(step == current ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                            .fixedSize()
                            .transition(.opacity)
                    }
                }
            }
        }
        .animation(.snappy, value: current)
        .animation(.snappy, value: isFinished)
        .accessibilityElement()
        .accessibilityLabel(
            "Step \((steps.firstIndex(of: current) ?? 0) + 1) of \(steps.count), \(current.title)")
    }

    private func heat(for step: ProvisioningStep) -> Heat {
        if step.rawValue < current.rawValue || (step == current && isFinished) { return .lit }
        return step == current ? .warming : .cold
    }
}

#Preview {
    VStack(spacing: 24) {
        ProvisioningSteps(current: .create)
        ProvisioningSteps(current: .setUp)
        ProvisioningSteps(current: .start, isFinished: true)
    }
    .padding(40)
}

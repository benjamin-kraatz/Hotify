import SwiftUI

/// A pull request number in the preview blue, wherever a preview shows up beside production.
struct PullRequestBadge: View {
    var number: Int

    @SwiftUI.Environment(\.backgroundProminence) private var prominence

    var body: some View {
        Label {
            Text(verbatim: "#\(number)")
                .monospacedDigit()
        } icon: {
            Image(systemName: "arrow.triangle.pull")
        }
        .labelStyle(BadgeLabelStyle())
        .font(.caption.weight(.semibold))
        .foregroundStyle(prominence == .increased ? AnyShapeStyle(.white) : AnyShapeStyle(.pilot))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(
            prominence == .increased ? AnyShapeStyle(.white.opacity(0.2)) : AnyShapeStyle(.pilot.opacity(0.13)),
            in: .capsule
        )
        .fixedSize()
        .accessibilityElement()
        .accessibilityLabel("Pull request \(number)")
    }
}

private struct BadgeLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
                .imageScale(.small)
            configuration.title
        }
    }
}

#Preview {
    HStack {
        PullRequestBadge(number: 42)
        PullRequestBadge(number: 1_204)
    }
    .padding()
}

import SwiftUI

/// What heads an environment in the dashboard list: its name, and how much of it runs.
struct EnvironmentHeading: View {
    var name: String
    /// The heat of each resource in the environment, with an action or deployment in flight counted as warming.
    var heats: [Heat]

    private var runningCount: Int { heats.count { $0 == .lit } }

    private var needsLook: Bool { heats.contains(where: \.needsAttention) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name.isEmpty ? "Environment" : name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text("\(runningCount) of \(heats.count) running")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(needsLook ? AnyShapeStyle(.glow) : AnyShapeStyle(.tertiary))
                .contentTransition(.numericText())
                .lineLimit(1)
                .layoutPriority(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .animation(.snappy, value: runningCount)
    }
}

#Preview {
    VStack(spacing: 12) {
        EnvironmentHeading(name: "production", heats: [.lit, .lit, .lit])
        EnvironmentHeading(name: "previews", heats: [.cold, .troubled, .cold])
    }
    .padding()
    .frame(width: 340)
}

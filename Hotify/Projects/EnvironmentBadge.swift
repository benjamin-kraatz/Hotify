import SwiftUI

/// An environment's name in a capsule, beside the project or resource it qualifies. A colored environment
/// leads with its dot and washes the capsule in its color.
struct EnvironmentBadge: View {
    var name: String
    var tint: PlaceTint?

    private var fill: AnyShapeStyle {
        if let tint {
            return AnyShapeStyle(tint.color.opacity(0.16))
        }
        return AnyShapeStyle(.quaternary.opacity(0.7))
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            PlaceMark(tint: tint)
            Text(name)
                .foregroundStyle(.secondary)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(fill, in: .capsule)
        .lineLimit(1)
    }
}

#Preview {
    HStack {
        EnvironmentBadge(name: "production")
        EnvironmentBadge(name: "staging", tint: .orange)
    }
    .padding()
}

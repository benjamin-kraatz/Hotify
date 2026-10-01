import SwiftUI

/// An environment's name in a capsule, beside the project or resource it qualifies.
struct EnvironmentBadge: View {
    var name: String

    var body: some View {
        Text(name)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.7), in: .capsule)
            .lineLimit(1)
    }
}

#Preview {
    HStack {
        EnvironmentBadge(name: "production")
        EnvironmentBadge(name: "staging")
    }
    .padding()
}

import SwiftUI

/// A small capsule for facts like `Literal` or `Draft`. Pull request numbers use `PullRequestBadge`.
struct Chip: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.7), in: .capsule)
            .fixedSize()
    }
}

#Preview {
    HStack {
        Chip(text: "Draft")
        Chip(text: "Literal")
    }
    .padding()
}

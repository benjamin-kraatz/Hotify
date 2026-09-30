import SwiftUI

/// A small capsule for facts like `Literal` or a pull request number.
struct Tag: View {
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
        Tag(text: "PR 18")
        Tag(text: "Literal")
    }
    .padding()
}

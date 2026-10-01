import SwiftUI

/// The capsule field above a list that narrows it as you type.
struct FilterField: View {
    var prompt: String
    @Binding var text: String

    init(_ prompt: String, text: Binding<String>) {
        self.prompt = prompt
        _text = text
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                #if os(iOS)
            .textInputAutocapitalization(.never)
                #endif
            if !text.isEmpty {
                Button("Clear filter", systemImage: "xmark.circle.fill") {
                    text = ""
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.6), in: .capsule)
        .animation(.snappy, value: text.isEmpty)
    }
}

#Preview {
    @Previewable @State var text = "API"
    FilterField("Filter keys", text: $text)
        .padding()
        .frame(width: 320)
}

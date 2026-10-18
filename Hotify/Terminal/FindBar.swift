import SwiftUI

/// Searches the scrollback. Return finds the next match, Shift-Return the one before, and Escape closes the bar.
struct FindBar: View {
    @Binding var term: String
    /// Where the current match sits, once a search ran.
    var matches: (index: Int, total: Int)?
    /// Jumps forward, or back with `false`.
    var onFind: (Bool) -> Void
    var onClose: () -> Void

    @FocusState private var isFocused: Bool

    private var summary: String? {
        guard let matches, !term.isEmpty else { return nil }
        // SwiftTerm counts from 1, and says 0 while nothing is selected yet.
        switch (matches.index, matches.total) {
        case (_, 0): return "No matches"
        case (0, let total): return total == 1 ? "1 match" : "\(total) matches"
        case (let index, let total): return "\(index) of \(total)"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find in scrollback", text: $term)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                #if os(iOS)
            .textInputAutocapitalization(.never)
                #endif
                .focused($isFocused)
                .onSubmit { onFind(true) }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    onFind(false)
                    return .handled
                }
                .onKeyPress(.escape) {
                    onClose()
                    return .handled
                }
            if let summary {
                Text(summary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(matches?.total == 0 ? AnyShapeStyle(.glow) : AnyShapeStyle(.secondary))
                    .contentTransition(.numericText())
            }
            Button("Previous match", systemImage: "chevron.up") { onFind(false) }
                .disabled(term.isEmpty)
            Button("Next match", systemImage: "chevron.down") { onFind(true) }
                .disabled(term.isEmpty)
            Button("Done", action: onClose)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .task { isFocused = true }
        .animation(.snappy, value: summary)
    }
}

#Preview {
    @Previewable @State var term = "error"
    VStack(spacing: 0) {
        FindBar(term: $term, matches: (index: 3, total: 14), onFind: { _ in }, onClose: {})
        FindBar(term: $term, matches: (index: 0, total: 0), onFind: { _ in }, onClose: {})
    }
    .frame(width: 520)
}

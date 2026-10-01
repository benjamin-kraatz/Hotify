import SwiftUI

/// The capsule field above a list that narrows it as you type.
///
/// Its icon can open a menu of filters beyond the text. It lights up while any of them is on.
struct FilterField<Filters: View>: View {
    var prompt: String
    @Binding var text: String
    /// Whether a filter from the menu is narrowing the list right now.
    var isFiltered: Bool
    var filters: Filters

    /// A field whose icon opens `filters` as a menu.
    init(_ prompt: String, text: Binding<String>, isFiltered: Bool, @ViewBuilder filters: () -> Filters) {
        self.prompt = prompt
        _text = text
        self.isFiltered = isFiltered
        self.filters = filters()
    }

    var body: some View {
        HStack(spacing: 6) {
            icon
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
        .animation(.snappy, value: isFiltered)
    }

    @ViewBuilder
    private var icon: some View {
        if Filters.self == EmptyView.self {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(.secondary)
        } else {
            Menu {
                filters
            } label: {
                Label(
                    "Filters",
                    systemImage: isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease"
                )
                .labelStyle(.iconOnly)
                .foregroundStyle(isFiltered ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
                .contentShape(.rect)
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .help(isFiltered ? "Filters are on. Click to change them." : "Filter the list")
        }
    }
}

extension FilterField where Filters == EmptyView {
    /// A field that filters by text alone. Its icon is only a mark.
    init(_ prompt: String, text: Binding<String>) {
        self.init(prompt, text: text, isFiltered: false) {
            EmptyView()
        }
    }
}

#Preview {
    @Previewable @State var text = "API"
    @Previewable @State var isOn = true
    VStack(spacing: 16) {
        FilterField("Filter keys", text: $text)
        FilterField("Filter resources", text: $text, isFiltered: isOn) {
            Toggle("Running", isOn: $isOn)
        }
    }
    .padding()
    .frame(width: 320)
}

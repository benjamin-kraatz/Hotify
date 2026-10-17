import SwiftUI

/// The row of sections under the detail header: each title, with a count where one helps, and an ember line under the
/// open one. Scrolls sideways when the column is too narrow for all of them.
struct DetailTabBar: View {
    var tabs: [DetailTab]
    @Binding var selection: DetailTab
    /// How many things a tab holds, such as containers or variables. Tabs without one show none.
    var counts: [DetailTab: Int] = [:]

    @Namespace private var underline
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 22) {
                ForEach(tabs) { tab in
                    button(tab)
                }
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func button(_ tab: DetailTab) -> some View {
        let isSelected = tab == selection
        return Button {
            withAnimation(reduceMotion ? nil : .snappy) {
                selection = tab
            }
        } label: {
            HStack(spacing: 6) {
                Text(tab.title)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                if let count = counts[tab], count > 0 {
                    Text(count, format: .number)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary.opacity(0.7), in: .capsule)
                }
            }
            .font(.callout)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                if isSelected {
                    Capsule()
                        .fill(.ember)
                        .frame(height: 2)
                        .matchedGeometryEffect(id: "underline", in: underline)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var tab = DetailTab.overview
    DetailTabBar(
        tabs: [.overview, .logs, .containers, .tasks, .storage, .variables],
        selection: $tab,
        counts: [.containers: 2, .variables: 14]
    )
    .frame(width: 560)
    .padding(.vertical)
}

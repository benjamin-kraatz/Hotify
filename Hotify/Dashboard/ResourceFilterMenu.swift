import SwiftUI

/// What the dashboard's filter menu holds: a tick per state and per kind, and a way to clear them.
struct ResourceFilterMenu: View {
    @Binding var filter: ResourceFilter

    /// The order the list itself puts kinds in.
    private static let kinds: [ResourceKind] = [.application, .service, .database]

    var body: some View {
        Section("State") {
            ForEach(ResourceStateFilter.allCases) { state in
                Toggle(isOn: isOn(state, in: \.states)) {
                    Label(state.title, systemImage: state.systemImage)
                }
            }
        }
        Section("Kind") {
            ForEach(Self.kinds, id: \.self) { kind in
                Toggle(isOn: isOn(kind, in: \.kinds)) {
                    Label(kind.pluralTitle, systemImage: kind.systemImage)
                }
            }
        }
        if filter.isActive {
            Divider()
            Button("Clear Filters", systemImage: "xmark") {
                filter = ResourceFilter()
            }
        }
    }

    private func isOn<Value: Hashable>(
        _ value: Value, in set: WritableKeyPath<ResourceFilter, Set<Value>>
    ) -> Binding<Bool> {
        Binding(
            get: { filter[keyPath: set].contains(value) },
            set: { isOn in
                if isOn {
                    filter[keyPath: set].insert(value)
                } else {
                    filter[keyPath: set].remove(value)
                }
            }
        )
    }
}

#Preview {
    @Previewable @State var filter = ResourceFilter(states: [.needsLook])
    Menu("Filters") {
        ResourceFilterMenu(filter: $filter)
    }
    .padding(40)
}

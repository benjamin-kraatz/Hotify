import SwiftUI

/// What the dashboard's filter menu holds: a tick per state, per kind, and per team tag, and a way to clear them.
struct ResourceFilterMenu: View {
    @Binding var filter: ResourceFilter
    /// The team's tag names. The menu lists these and nothing else.
    var tags: [String] = []

    /// The order the list itself puts kinds in.
    private static let kinds: [ResourceKind] = [.application, .service, .database]

    private var tagNames: [String] {
        var seen: Set<String> = []
        return tags.filter { seen.insert($0).inserted }
    }

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
        if !tagNames.isEmpty {
            Section("Tags") {
                ForEach(tagNames, id: \.self) { tag in
                    Toggle(isOn: isOn(tag, in: \.tags)) {
                        Label(tag, systemImage: "tag")
                    }
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

#Preview("Filters off") {
    @Previewable @State var filter = ResourceFilter()
    @Previewable @State var query = ""
    FilterField("Filter resources", text: $query, isFiltered: filter.isActive) {
        ResourceFilterMenu(filter: $filter, tags: ["prod", "staging", "web"])
    }
    .padding()
    .frame(width: 360)
}

#Preview("Tag selected") {
    @Previewable @State var filter = ResourceFilter(tags: ["prod"])
    @Previewable @State var query = ""
    FilterField("Filter resources", text: $query, isFiltered: filter.isActive) {
        ResourceFilterMenu(filter: $filter, tags: ["prod", "staging", "web"])
    }
    .padding()
    .frame(width: 360)
}

import SwiftUI

/// A dashboard section title: the project, then its environment in a capsule. It opens the project's page.
struct GroupHeader: View {
    var place: ResourcePlace?
    /// The project's page is open in the detail column.
    var isOpen = false
    /// `nil` leaves a plain title, as for resources Hotify could not place.
    var onOpen: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        Group {
            if let place, let onOpen {
                Button(action: onOpen) {
                    title(place, opens: true)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .onHover { isHovered = $0 }
                .help("Show the \(place.projectName) project")
                .accessibilityHint("Shows the project")
                .accessibilityAddTraits(isOpen ? [.isHeader, .isSelected] : .isHeader)
            } else if let place {
                title(place, opens: false)
            } else {
                Text("Other")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        // iOS capitalizes list headers. Project and environment names keep the case the user gave them.
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .animation(.snappy(duration: 0.15), value: isHovered)
        .animation(.snappy, value: isOpen)
    }

    private func title(_ place: ResourcePlace, opens: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(place.projectName)
                .font(.headline)
                .foregroundStyle(isOpen ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .lineLimit(1)
            if !place.environmentName.isEmpty {
                EnvironmentBadge(name: place.environmentName)
            }
            if opens {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        isOpen
                            ? AnyShapeStyle(.tint)
                            : AnyShapeStyle(isHovered ? HierarchicalShapeStyle.secondary : .tertiary)
                    )
                    .accessibilityHidden(true)
            }
        }
    }
}

#Preview {
    let website = ResourcePlace(
        projectID: "website", projectName: "Website", environmentName: "production", environmentID: 1)
    List {
        Section {
            Text("marketing-site")
        } header: {
            GroupHeader(place: website, onOpen: {})
        }
        Section {
            Text("api")
        } header: {
            GroupHeader(place: website, isOpen: true, onOpen: {})
        }
        Section {
            Text("postgres")
        } header: {
            GroupHeader(place: nil)
        }
    }
    .frame(width: 380, height: 320)
}

import SwiftUI

/// A dashboard section title: the project, then its environment in a capsule.
struct GroupHeader: View {
    var place: ResourcePlace?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let place {
                Text(place.projectName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !place.environmentName.isEmpty {
                    Text(place.environmentName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.quaternary.opacity(0.7), in: .capsule)
                        .lineLimit(1)
                }
            } else {
                Text("Other")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        // iOS capitalizes list headers. Project and environment names keep the case the user gave them.
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    List {
        Section {
            Text("marketing-site")
        } header: {
            GroupHeader(place: ResourcePlace(projectName: "Website", environmentName: "production", environmentID: 1))
        }
        Section {
            Text("postgres")
        } header: {
            GroupHeader(place: nil)
        }
    }
    .frame(width: 380, height: 260)
}

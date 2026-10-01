import SwiftUI

/// What heads a project in the dashboard list: its name, a tick of heat per resource, and the way in to its page.
///
/// A project with one environment names it here. One with several labels them further down instead, so the
/// project's name shows once however many it has.
struct ProjectSectionHeader: View {
    var section: ProjectSection
    /// The heat of each of the project's resources, with an action or deployment in flight counted as warming.
    var heats: [Heat]

    private var runningCount: Int { heats.count { $0 == .lit } }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(section.name)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            if let environment = section.soleEnvironmentName {
                EnvironmentBadge(name: environment)
            }
            Spacer(minLength: 8)
            if heats.isEmpty {
                Text("Empty")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
            } else {
                // A short bar per resource, up to a fixed width, so a project of thirty does not push its own
                // name out.
                HeatStrip(heats: heats, height: 6)
                    .frame(width: min(CGFloat(heats.count) * 14 - 3, 110))
            }
            if section.projectID != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(section.name)
        .accessibilityValue(
            heats.isEmpty ? "Empty" : "\(runningCount) of \(heats.count) running"
        )
    }
}

#Preview {
    let production = ResourcePlace(
        projectID: "website", projectName: "Website", environmentName: "production", environmentID: 1)
    VStack(spacing: 16) {
        ProjectSectionHeader(
            section: ProjectSection(
                projectID: "website",
                name: "Website",
                environments: [
                    EnvironmentSection(
                        id: 1, name: "production",
                        resources: [ResourceSummary(route: .application("web"), name: "web", place: production)])
                ]
            ),
            heats: [.lit, .lit, .troubled, .cold]
        )
        ProjectSectionHeader(section: ProjectSection(projectID: "new", name: "Side project"), heats: [])
        ProjectSectionHeader(section: ProjectSection(name: "Other"), heats: [.lit])
    }
    .padding()
    .frame(width: 380)
}

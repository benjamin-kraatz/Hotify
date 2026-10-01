import SwiftUI

/// What heads a project in the dashboard list: its name with the way in to its page, and under it a bar of heat
/// with a tick per resource.
///
/// The name has the line to itself and may take a second, so it is the last thing to be cut short. Environments
/// are named further down, each above its own resources.
struct ProjectSectionHeader: View {
    var section: ProjectSection
    /// The heat of each of the project's resources, with an action or deployment in flight counted as warming.
    var heats: [Heat]

    private var runningCount: Int { heats.count { $0 == .lit } }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(section.name)
                    .font(.headline)
                    // A long name takes a second line before it is cut.
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                if heats.isEmpty {
                    Text("Empty")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if section.projectID != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            if !heats.isEmpty {
                HeatStrip(heats: heats, height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(section.name)
        .accessibilityValue(heats.isEmpty ? "Empty" : "\(runningCount) of \(heats.count) running")
    }
}

#Preview {
    VStack(spacing: 20) {
        ProjectSectionHeader(
            section: ProjectSection(projectID: "website", name: "A project with quite a long name to fit"),
            heats: [.lit, .lit, .troubled, .cold, .cold, .cold, .cold, .cold, .cold]
        )
        ProjectSectionHeader(section: ProjectSection(projectID: "new", name: "Side project"), heats: [])
        ProjectSectionHeader(section: ProjectSection(name: "Other"), heats: [.lit])
    }
    .padding()
    .frame(width: 320)
}

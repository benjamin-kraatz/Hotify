import SwiftUI

/// The top of the project page: one flame for the whole project, its name, how much of it runs, and what it is for.
struct ProjectHeader: View {
    var project: ProjectSummary
    /// The heat of every resource in the project, with actions and deployments in flight counted as warming.
    var heats: [Heat]
    /// Fills the folder beside "Project" with the project's color.
    var tint: PlaceTint?

    private var runningCount: Int { heats.count { $0 == .lit } }

    private var troubledCount: Int { heats.count { $0 == .troubled } }

    /// Work in flight leads, because it changes soonest. Then trouble, then anything that runs.
    private var heat: Heat {
        if heats.isEmpty { return .unknown }
        if heats.contains(.warming) { return .warming }
        if heats.contains(.troubled) { return .troubled }
        return heats.contains(.lit) ? .lit : .cold
    }

    private var statusText: String {
        heats.isEmpty ? "Nothing deployed yet" : "\(runningCount) of \(heats.count) running"
    }

    private var facts: String {
        var facts: [String] = []
        let count = project.environments.count
        if count > 0 {
            facts.append(count == 1 ? "1 environment" : "\(count) environments")
        }
        if let createdAt = project.createdAt {
            facts.append("Created \(createdAt.formatted(date: .abbreviated, time: .omitted))")
        }
        return facts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 18) {
                FlameGlyph(heat: heat, height: 56, ignitesOnAppear: true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(project.name)
                        .font(.display(.title))
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .textSelection(.enabled)

                    // On one line when it fits. A phone puts what needs a look on a line of its own.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            status
                            attention
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            status
                            attention
                        }
                    }
                    .font(.subheadline)
                    .monospacedDigit()
                    .lineLimit(1)

                    if let description = project.description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }

                    if !facts.isEmpty {
                        Text(facts)
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            if !heats.isEmpty {
                // Capped per tick, so a project of three resources does not draw three bars across a wide window.
                HeatStrip(heats: heats)
                    .frame(maxWidth: CGFloat(heats.count) * 44, alignment: .leading)
            }
        }
        .animation(.snappy, value: heat)
        .animation(.snappy, value: statusText)
        .animation(.snappy, value: troubledCount)
        .animation(.snappy, value: project)
    }

    private var status: some View {
        HStack(spacing: 12) {
            Label {
                Text("Project")
            } icon: {
                if let tint {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(tint.color)
                } else {
                    Image(systemName: "folder")
                }
            }
            .foregroundStyle(.secondary)
            Text(statusText)
                .fontWeight(.semibold)
                .foregroundStyle(heat.tint)
                .contentTransition(.numericText())
        }
    }

    @ViewBuilder
    private var attention: some View {
        if troubledCount > 0 {
            Label(
                troubledCount == 1 ? "1 needs a look" : "\(troubledCount) need a look",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.glow)
            .contentTransition(.numericText())
            .transition(.opacity)
        }
    }
}

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 40) {
            ProjectHeader(
                project: ProjectSummary(
                    id: "website",
                    name: "Website",
                    description: "The marketing site, its API, and what they store.",
                    createdAt: .now.addingTimeInterval(-86_400 * 200),
                    environments: [
                        EnvironmentSummary(id: 1, name: "production"),
                        EnvironmentSummary(id: 2, name: "staging"),
                    ]
                ),
                heats: [.lit, .lit, .lit, .troubled, .cold, .cold],
                tint: .teal
            )
            ProjectHeader(
                project: ProjectSummary(
                    id: "tools", name: "Internal tools", environments: [EnvironmentSummary(id: 3, name: "production")]),
                heats: [.lit, .warming]
            )
            ProjectHeader(project: ProjectSummary(id: "new", name: "Side project"), heats: [])
        }
        .padding(24)
    }
    .frame(width: 560)
}

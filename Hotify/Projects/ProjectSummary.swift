import CoolifyAPI
import Foundation

/// One project, cut down to the plain values its page shows.
struct ProjectSummary: Identifiable, Hashable {
    /// The project's uuid.
    var id: String
    var name: String
    var description: String?
    var createdAt: Date?
    /// Oldest first, the order Coolify creates them in, so production usually leads.
    var environments: [EnvironmentSummary] = []
}

/// One environment of a project. It may hold no resources at all.
struct EnvironmentSummary: Identifiable, Hashable {
    var id: Int
    /// What Coolify's routes take for this environment. The name stands in when the uuid is missing.
    var uuid: String?
    var name: String
    var description: String?

    /// The uuid when Coolify sent one, else the name. Coolify's environment routes accept either.
    var reference: String { uuid ?? name }
}

extension ProjectSummary {
    /// `detail` is the same project from `GET /projects/{uuid}`, which adds the environments and the creation date.
    /// The listed project is newer, so its name and description win.
    init(project: Project, detail: Project?) {
        id = project.uuid
        name = project.name.flatMap { $0.isEmpty ? nil : $0 } ?? project.uuid
        description = Self.cleaned(project.description)
        createdAt = detail?.createdAtDate
        environments = (detail?.environments ?? [])
            .compactMap { environment in
                guard let id = environment.id else { return nil }
                return EnvironmentSummary(
                    id: id,
                    uuid: environment.uuid.flatMap { $0.isEmpty ? nil : $0 },
                    name: environment.name ?? "",
                    description: Self.cleaned(environment.description)
                )
            }
            .sorted { $0.id < $1.id }
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

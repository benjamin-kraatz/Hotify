import CoolifyAPI
import SwiftUI

/// Moves a resource into another environment. Running containers stay up.
struct MoveSheet: View {
    var resourceName: String
    var route: ResourceRoute
    var client: CoolifyClient?

    @Bindable var catalog: MoveCatalog
    @State private var isSaving = false
    @State private var confirm = false
    @State private var failure: String?
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @SwiftUI.Environment(\.placePalette) private var palette

    private var canMove: Bool {
        guard !isSaving, catalog.hasLoaded, let environmentUUID = catalog.environmentUUID, !environmentUUID.isEmpty
        else { return false }
        return environmentUUID != catalog.currentEnvironmentUUID
    }

    private var moveNote: String {
        var note =
            "Running containers stay up. This only changes which environment \(resourceName) belongs to. "
            + "It picks up that environment's shared variables on the next deploy."
        if let current = catalog.currentEnvironmentUUID, catalog.environmentUUID == current {
            note += " \(resourceName) is already in this environment."
        }
        return note
    }

    private var confirmation: String {
        "Running containers stay up. \(resourceName) will belong to \(catalog.environmentName). "
            + "It picks up that environment's shared variables on the next deploy."
    }

    var body: some View {
        PlacementChrome(
            title: "Move", actionTitle: "Move", canAct: canMove, isBusy: isSaving, failure: failure,
            onAct: { confirm = true }
        ) {
            Section {
                if !catalog.hasLoaded, catalog.problem == nil || catalog.isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading projects…")
                            .foregroundStyle(.secondary)
                    }
                } else if let problem = catalog.problem, !catalog.hasLoaded {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.glow)
                        Button("Try Again", systemImage: "arrow.clockwise") {
                            Task { await catalog.load() }
                        }
                    }
                } else if catalog.projects.isEmpty {
                    Text("This team has no projects yet.")
                        .foregroundStyle(.secondary)
                } else {
                    projectPicker
                    if catalog.environments.isEmpty {
                        Text("This project has no environment to move into.")
                            .foregroundStyle(.secondary)
                    } else {
                        environmentPicker
                    }
                }
            } header: {
                Text("Environment")
            } footer: {
                Text(moveNote)
            }
        }
        .confirmationDialog("Move \(resourceName)?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Move") { Task { await move() } }
        } message: {
            Text(confirmation)
        }
        .task {
            catalog.prepare(client)
            await catalog.load()
        }
    }

    private var projectPicker: some View {
        Picker(
            selection: Binding(
                get: { catalog.projectUUID ?? "" },
                set: { catalog.selectProject($0) })
        ) {
            ForEach(catalog.projects, id: \.uuid) { project in
                Text(project.name ?? project.uuid).tag(project.uuid)
            }
        } label: {
            placeLabel(
                "Project", systemImage: "folder", coloredImage: "folder.fill",
                tint: palette.project(catalog.projectUUID))
        }
    }

    private var environmentPicker: some View {
        Picker(
            selection: Binding(
                get: { catalog.environmentUUID ?? "" },
                set: { catalog.selectEnvironment($0) })
        ) {
            ForEach(catalog.environments, id: \.uuid) { environment in
                Text(environment.name ?? "Unnamed").tag(environment.uuid ?? "")
            }
        } label: {
            placeLabel(
                "Environment", systemImage: "square.3.layers.3d", coloredImage: "square.3.layers.3d",
                tint: palette.environment(catalog.environmentUUID))
        }
        .disabled(catalog.project == nil)
    }

    /// The picker's label. Its icon takes the color of the project or environment picked.
    private func placeLabel(
        _ title: String, systemImage: String, coloredImage: String, tint: PlaceTint?
    ) -> some View {
        Label {
            Text(title)
        } icon: {
            if let tint {
                Image(systemName: coloredImage)
                    .foregroundStyle(tint.color)
            } else {
                Image(systemName: systemImage)
            }
        }
    }

    private func move() async {
        guard !isSaving, let client, let environmentUUID = catalog.environmentUUID else {
            failure = client == nil ? "Hotify is not connected to this instance." : failure
            return
        }
        guard environmentUUID != catalog.currentEnvironmentUUID else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await client.moveResource(PlacementOwner(route), to: environmentUUID)
            dismiss()
        } catch {
            failure = placementFailure(error)
        }
    }
}

#Preview {
    @Previewable @State var catalog = MoveCatalog(
        projects: [
            Project(
                uuid: "website", name: "Website",
                environments: [
                    Environment(id: 1, uuid: "env-prod", name: "production"),
                    Environment(id: 2, uuid: "env-staging", name: "staging"),
                ]),
            Project(
                uuid: "api", name: "API",
                environments: [
                    Environment(id: 3, uuid: "env-api", name: "production")
                ]),
        ],
        projectUUID: "website",
        environmentUUID: "env-staging",
        currentEnvironmentUUID: "env-prod"
    )
    MoveSheet(resourceName: "marketing-site", route: .application("app"), client: nil, catalog: catalog)
        .environment(\.placePalette, .preview(projects: ["website": .teal], environments: ["env-staging": .indigo]))
}

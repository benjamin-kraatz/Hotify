import CoolifyAPI
import SwiftUI

/// The form section that picks where a new service runs: server, project, environment, and network if there is a
/// choice. A project or environment can be made on the spot.
struct PlacementSection: View {
    var model: PlacementModel

    @State private var naming: NewPlace?
    @State private var newName = ""

    private enum NewPlace: Identifiable {
        case project
        case environment

        var id: Self { self }
    }

    /// A picker row value that opens the naming alert instead of selecting.
    private static let newTag = "hotify.new"

    var body: some View {
        Section {
            if !model.hasLoaded {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading servers and projects…")
                        .foregroundStyle(.secondary)
                }
            } else {
                serverPicker
                projectPicker
                environmentPicker
                if !model.destinations.isEmpty {
                    networkPicker
                }
            }
        } header: {
            Text("Where it runs")
        } footer: {
            if let server = model.server, !model.isReachable(server) {
                Label(
                    "Coolify can't reach \(server.name) right now. The service is created, but may not start until it can.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.glow)
            } else if model.hasLoaded, model.hostServers.isEmpty {
                Text("This team has no server that can run services. Add one in Coolify first.")
            } else if model.hasLoaded, model.projects.isEmpty {
                Text("This team has no projects yet. Make one to hold the service.")
            }
        }
        .alert(naming == .project ? "New Project" : "New Environment", isPresented: isNaming, presenting: naming) {
            place in
            TextField(place == .project ? "Project name" : "Environment name", text: $newName)
            Button("Create") { create(place) }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: { place in
            Text(
                place == .project
                    ? "Coolify gives a new project a production environment to start with."
                    : "Environments keep copies apart, like staging and production, inside \(model.project?.name ?? "the project")."
            )
        }
    }

    private var serverPicker: some View {
        Picker(
            selection: Binding(
                get: { model.placement.serverUUID ?? "" },
                set: { uuid in
                    Task { await model.selectServer(uuid) }
                })
        ) {
            ForEach(model.hostServers, id: \.uuid) { server in
                Text(model.isReachable(server) ? server.name : "\(server.name) (unreachable)")
                    .tag(server.uuid)
            }
        } label: {
            Label("Server", systemImage: "server.rack")
        }
    }

    private var projectPicker: some View {
        Picker(
            selection: Binding(
                get: { model.placement.projectUUID ?? "" },
                set: { uuid in
                    if uuid == Self.newTag { name(.project) } else { model.selectProject(uuid) }
                })
        ) {
            ForEach(model.projects, id: \.uuid) { project in
                Text(project.name ?? project.uuid).tag(project.uuid)
            }
            Divider()
            Text("New Project…").tag(Self.newTag)
        } label: {
            Label("Project", systemImage: "folder")
        }
        .disabled(model.isCreatingPlace)
    }

    private var environmentPicker: some View {
        Picker(
            selection: Binding(
                get: { model.placement.environmentUUID ?? "" },
                set: { uuid in
                    if uuid == Self.newTag { name(.environment) } else { model.selectEnvironment(uuid) }
                })
        ) {
            ForEach(model.environments, id: \.uuid) { environment in
                Text(environment.name ?? "Unnamed").tag(environment.uuid ?? "")
            }
            Divider()
            Text("New Environment…").tag(Self.newTag)
        } label: {
            Label("Environment", systemImage: "square.3.layers.3d")
        }
        .disabled(model.project == nil || model.isCreatingPlace)
    }

    private var networkPicker: some View {
        Picker(
            selection: Binding(
                get: { model.placement.destinationUUID ?? "" }, set: { model.placement.destinationUUID = $0 })
        ) {
            ForEach(model.destinations) { destination in
                Text(destination.network.map { "\(destination.name) (\($0))" } ?? destination.name)
                    .tag(destination.uuid)
            }
        } label: {
            Label("Network", systemImage: "network")
        }
    }

    private var isNaming: Binding<Bool> {
        Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })
    }

    private func name(_ place: NewPlace) {
        newName = ""
        naming = place
    }

    private func create(_ place: NewPlace) {
        let name = newName
        Task {
            switch place {
            case .project: await model.createProject(named: name)
            case .environment: await model.createEnvironment(named: name)
            }
        }
    }
}

#Preview {
    Form {
        PlacementSection(
            model: PlacementModel(
                servers: [
                    Server(uuid: "s1", name: "localhost", isReachable: true),
                    Server(uuid: "s2", name: "edge-01", isReachable: false),
                ],
                projects: [
                    Project(
                        uuid: "p1", name: "Website",
                        environments: [
                            Environment(uuid: "e1", name: "production"), Environment(uuid: "e2", name: "staging"),
                        ])
                ],
                placement: Placement(serverUUID: "s1", projectUUID: "p1", environmentUUID: "e1")
            )
        )
    }
    .formStyle(.grouped)
    .frame(width: 520, height: 320)
}

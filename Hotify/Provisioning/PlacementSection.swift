import CoolifyAPI
import SwiftUI

/// The form section that picks where a new service runs: server, project, environment, and network if there is a
/// choice. A project or environment can be made on the spot, with its color.
struct PlacementSection: View {
    var model: PlacementModel

    @State private var naming: PlaceKind?
    @SwiftUI.Environment(\.placePalette) private var palette

    /// A picker row value that opens the naming popover instead of selecting.
    private static let newTag = "hotify.new"

    var body: some View {
        Section {
            if !model.hasLoaded, model.problem != nil, !model.isLoading {
                HStack {
                    Text("Servers and projects didn't load.")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Button("Try Again", systemImage: "arrow.clockwise") {
                        Task { await model.load() }
                    }
                }
            } else if !model.hasLoaded {
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
    }

    private var serverPicker: some View {
        Picker(
            selection: Binding(
                get: { model.placement.serverUUID ?? "" },
                set: { uuid in
                    model.selectServer(uuid)
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
                    if uuid == Self.newTag { naming = .project } else { model.selectProject(uuid) }
                })
        ) {
            ForEach(model.projects, id: \.uuid) { project in
                Text(project.name ?? project.uuid).tag(project.uuid)
            }
            Divider()
            Text("New Project…").tag(Self.newTag)
        } label: {
            placeLabel(
                "Project", systemImage: "folder", coloredImage: "folder.fill",
                tint: palette.project(model.placement.projectUUID))
        }
        .disabled(model.isCreatingPlace)
        .popover(isPresented: isNaming(.project), arrowEdge: .bottom) {
            NewPlacePopover(kind: .project, takenNames: Set(model.projects.compactMap(\.name))) { name, tint in
                let uuid = try await model.createProject(named: name)
                if let tint {
                    palette.setProject(tint, for: uuid)
                }
            }
        }
    }

    private var environmentPicker: some View {
        Picker(
            selection: Binding(
                get: { model.placement.environmentUUID ?? "" },
                set: { uuid in
                    if uuid == Self.newTag { naming = .environment } else { model.selectEnvironment(uuid) }
                })
        ) {
            ForEach(model.environments, id: \.uuid) { environment in
                Text(environment.name ?? "Unnamed").tag(environment.uuid ?? "")
            }
            Divider()
            Text("New Environment…").tag(Self.newTag)
        } label: {
            placeLabel(
                "Environment", systemImage: "square.3.layers.3d", coloredImage: "square.3.layers.3d",
                tint: palette.environment(model.placement.environmentUUID))
        }
        .disabled(model.project == nil || model.isCreatingPlace)
        .popover(isPresented: isNaming(.environment), arrowEdge: .bottom) {
            NewPlacePopover(
                kind: .environment,
                note:
                    "Environments keep copies apart, like staging and production, inside \(model.project?.name ?? "the project").",
                takenNames: Set(model.environments.compactMap(\.name))
            ) { name, tint in
                let uuid = try await model.createEnvironment(named: name)
                if let tint {
                    palette.setEnvironment(tint, for: uuid)
                }
            }
        }
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

    private func isNaming(_ kind: PlaceKind) -> Binding<Bool> {
        Binding(get: { naming == kind }, set: { if !$0 { naming = nil } })
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

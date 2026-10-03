import CoolifyAPI
import SwiftUI

/// One database engine, up close: where it should go, its name, image, and whether it's reachable from outside.
/// Creating it starts it.
struct DatabaseLaunchPad: View {
    var engine: DatabaseEngine
    var model: DatabaseProvisioningModel
    var instanceRoot: URL?

    var body: some View {
        @Bindable var model = model

        Form {
            Section {
            } header: {
                hero
            }

            PlacementSection(model: model.placement)

            Section {
                TextField("Name", text: $model.name, prompt: Text(verbatim: engine.rawValue))
                    .autocorrectionDisabled()
                    #if os(iOS)
                .textInputAutocapitalization(.never)
                    #endif
                TextField("Description", text: $model.description, prompt: Text("Optional"), axis: .vertical)
                    .lineLimit(1...3)
                TextField("Image", text: $model.image, prompt: Text("Coolify's default"))
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    #if os(iOS)
                .textInputAutocapitalization(.never)
                    #endif
            } header: {
                Text("Name")
            } footer: {
                Text("Leave the image empty for the version Coolify picks, or name one with its tag.")
            }

            Section {
                Toggle("Reachable from the internet", isOn: $model.isPublic)
                if model.isPublic {
                    NumberField(title: "Public port", value: $model.publicPort, prompt: String(engine.port))
                }
            } header: {
                Text("Public Access")
            } footer: {
                Text(
                    model.isPublic
                        ? "Coolify forwards this port on the server to the database. Anyone who can reach the server can try to sign in."
                        : "Only resources on the server's network can reach it."
                )
            }

            if let problem = model.createProblem ?? model.placement.problem {
                Section {
                    ProblemNotice(problem: problem, instanceRoot: instanceRoot)
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) { createBar }
        .disabled(model.isCreating)
        .animation(.snappy, value: model.isPublic)
        .animation(.snappy, value: model.createProblem)
        .onChange(of: model.placement.placement) { _, _ in model.createProblem = nil }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 18) {
            TemplateLogo(name: engine.displayName, url: engine.logoURL(instanceRoot: instanceRoot), size: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text(engine.displayName)
                    .font(.display(.title))
                    .foregroundStyle(.primary)
                Text(engine.slogan)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Port \(String(engine.port))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
        .padding(.bottom, 14)
        .accessibilityElement(children: .contain)
    }

    private var createBar: some View {
        HStack(spacing: 14) {
            FlameGlyph(heat: model.isCreating ? .warming : .cold, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.problem ?? (model.isCreating ? "Creating \(model.displayName)…" : "Ready to create"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(model.problem == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.glow))
                    .contentTransition(.interpolate)
                Text(destinationSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Button {
                Task { await model.create(engine) }
            } label: {
                Text("Create and Start")
                    .opacity(model.isCreating ? 0 : 1)
                    .overlay {
                        if model.isCreating {
                            ProgressView().controlSize(.small)
                        }
                    }
            }
            .glassButton(prominent: true)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canCreate)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
        .animation(.snappy, value: model.isCreating)
    }

    private var destinationSummary: String {
        let placement = model.placement
        guard let server = placement.server, let project = placement.project, let environment = placement.environment
        else { return "Pick a server, project, and environment." }
        return
            "On \(server.name), in \(project.name ?? project.uuid) · \(environment.name ?? ""). It starts right away."
    }
}

#Preview {
    let placement = PlacementModel(
        servers: [Server(uuid: "s1", name: "localhost", isReachable: true)],
        projects: [Project(uuid: "p1", name: "Website", environments: [Environment(uuid: "e1", name: "production")])],
        placement: Placement(serverUUID: "s1", projectUUID: "p1", environmentUUID: "e1")
    )
    NavigationStack {
        DatabaseLaunchPad(engine: .postgresql, model: DatabaseProvisioningModel(placement: placement))
    }
    .frame(width: 720, height: 760)
}

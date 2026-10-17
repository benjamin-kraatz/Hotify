import CoolifyAPI
import SwiftUI

/// One database engine, up close: where it should go, its name, image, and whether it's reachable from outside.
/// Creating it starts it.
struct DatabaseLaunchPad: View {
    var engine: DatabaseEngine
    var model: DatabaseProvisioningModel
    var instanceRoot: URL?

    @SwiftUI.Environment(\.isProvisioningInspector) private var isInspector

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
        HStack(alignment: .center, spacing: isInspector ? 14 : 18) {
            TemplateLogo(
                name: engine.displayName, url: engine.logoURL(instanceRoot: instanceRoot), size: isInspector ? 56 : 72)
            VStack(alignment: .leading, spacing: 6) {
                Text(engine.displayName)
                    .font(.display(isInspector ? .title2 : .title))
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
        CreateBar(
            isCreating: model.isCreating,
            status: model.problem ?? (model.isCreating ? "Creating \(model.displayName)…" : "Ready to create"),
            isProblem: model.problem != nil,
            summary: PlacementSummary.text(model.placement, then: "It starts right away."),
            buttonTitle: "Create and Start",
            canCreate: model.canCreate
        ) {
            Task { await model.create(engine) }
        }
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

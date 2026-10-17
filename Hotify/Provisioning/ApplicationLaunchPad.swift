import CoolifyAPI
import SwiftUI

/// One application source, up close: where it should run, the fields that source needs, and whether to deploy it now.
struct ApplicationLaunchPad: View {
    var source: NewApplicationSource
    var model: ApplicationProvisioningModel
    var instanceRoot: URL?
    /// Leaves out the repository, Dockerfile, or image, for the Mac sheet's inspector, where they take the middle
    /// column instead.
    var showsSource = true

    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SwiftUI.Environment(\.isProvisioningInspector) private var isInspector

    var body: some View {
        @Bindable var model = model

        Form {
            Section {
            } header: {
                hero
            }

            PlacementSection(model: model.placement)

            if showsSource {
                ApplicationSourceFields(source: source, model: model)
            }

            Section {
                TextField("Name", text: $model.name, prompt: Text("Optional"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                .textInputAutocapitalization(.never)
                    #endif
                if source == .publicGit {
                    TextField("Description", text: $model.description, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(1...3)
                }
                NumberField(title: "Exposed port", value: $model.port, prompt: "3000")
            } header: {
                Text("Name")
            } footer: {
                Text("Leave the port empty and Coolify chooses one. A name you leave empty is filled in for you.")
            }

            Section {
                Toggle("Deploy immediately", isOn: $model.instantDeploy)
            } footer: {
                Text(
                    model.instantDeploy
                        ? "Coolify builds and starts it as soon as it exists."
                        : "Coolify creates it and leaves it stopped."
                )
            }

            if let problem = model.createProblem ?? model.sourceProblem ?? model.placement.problem {
                Section {
                    ProblemNotice(problem: problem, instanceRoot: instanceRoot)
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) { createBar }
        .disabled(model.isCreating)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy, value: model.instantDeploy)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy, value: model.createProblem)
        .onChange(of: model.placement.placement) { _, _ in model.createProblem = nil }
        .task {
            // The gallery sets this too. The task repeats it so the catalog load cannot race the first frame.
            model.source = source
            await model.loadCatalog()
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: isInspector ? 14 : 18) {
            CatalogLogo(entry: .application(source), size: isInspector ? 56 : 72)
            VStack(alignment: .leading, spacing: 6) {
                Text(source.title)
                    .font(.display(isInspector ? .title2 : .title))
                    .foregroundStyle(.primary)
                Text(source.slogan)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textCase(nil)
        .padding(.bottom, 14)
        .accessibilityElement(children: .contain)
    }

    private var createBar: some View {
        CreateBar(
            isCreating: model.isCreating,
            status: model.statusLine,
            isProblem: model.problem != nil,
            summary: PlacementSummary.text(
                model.placement,
                then: model.instantDeploy ? "It deploys right away." : "It stays stopped until you start it."),
            buttonTitle: model.instantDeploy ? "Create and Deploy" : "Create",
            canCreate: model.canCreate
        ) {
            Task { await model.create() }
        }
    }
}

#Preview("Public repository") {
    launchPad(.publicGit)
}

#Preview("Dockerfile") {
    launchPad(.dockerfile)
}

#Preview("GitHub App") {
    launchPad(.githubApp)
}

private func launchPad(_ source: NewApplicationSource) -> some View {
    let placement = PlacementModel(
        servers: [Server(uuid: "s1", name: "localhost", isReachable: true)],
        projects: [Project(uuid: "p1", name: "Website", environments: [Environment(uuid: "e1", name: "production")])],
        placement: Placement(serverUUID: "s1", projectUUID: "p1", environmentUUID: "e1")
    )
    let model = ApplicationProvisioningModel(placement: placement)
    model.source = source
    return NavigationStack {
        ApplicationLaunchPad(source: source, model: model)
    }
    .frame(width: 720, height: 760)
}

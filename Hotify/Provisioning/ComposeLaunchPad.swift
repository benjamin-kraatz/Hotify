import CoolifyAPI
import SwiftUI

/// A service from a compose file the user writes or pastes: the file, where it goes, and its name. Creating it moves on
/// to the same setup a template gets.
struct ComposeLaunchPad: View {
    var model: ProvisioningModel
    var instanceRoot: URL?

    private var outline: ComposeOutline { ComposeOutline(model.compose) }

    /// Leaves out the editor, for the Mac sheet's inspector, where the file takes the middle column instead.
    var showsEditor = true

    @SwiftUI.Environment(\.isProvisioningInspector) private var isInspector

    private static let variablesNote =
        "Coolify fills SERVICE_PASSWORD_, SERVICE_USER_, and SERVICE_URL_ variables itself, and asks for the rest after it creates the service. For a compose file in a Git repository, create an application instead."

    private static var editorHeight: CGFloat {
        #if os(macOS)
        300
        #else
        240
        #endif
    }

    var body: some View {
        @Bindable var model = model

        Form {
            if showsEditor {
                Section {
                    // The editor draws its own well, so the row gives it the whole width and no second box.
                    ComposeEditor(compose: $model.compose, height: Self.editorHeight)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    VStack(alignment: .leading, spacing: 0) {
                        hero
                        Text("Compose File")
                    }
                } footer: {
                    Text(Self.variablesNote)
                }
            } else {
                Section {
                    if outline.containers.isEmpty {
                        Text("Write or paste the file, and Hotify lists what it runs here.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    hero
                } footer: {
                    Text(Self.variablesNote)
                }
            }

            if !outline.containers.isEmpty {
                Section {
                    ForEach(outline.containers) { container in
                        ContainerLine(name: container.name, image: container.image)
                    }
                } header: {
                    Text("Containers")
                } footer: {
                    Text(
                        outline.containers.count == 1
                            ? "One container. Coolify gives it its passwords and address when it creates the service."
                            : "\(outline.containers.count) containers, started together. Coolify gives them their passwords and addresses when it creates the service."
                    )
                }
            }

            PlacementSection(model: model.placement)

            Section {
                TextField("Name", text: $model.name, prompt: Text("Coolify picks one"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                .textInputAutocapitalization(.never)
                    #endif
                TextField("Description", text: $model.description, prompt: Text("Optional"), axis: .vertical)
                    .lineLimit(1...3)
            } header: {
                Text("Name")
            } footer: {
                Text("How it shows in Hotify and Coolify. You can rename it later.")
            }

            if let problem = model.createProblem ?? model.placement.problem {
                Section {
                    ProblemNotice(problem: problem, instanceRoot: instanceRoot)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { createBar }
        .disabled(model.isCreating)
        .animation(.snappy, value: model.createProblem)
        .animation(.snappy, value: model.placement.problem)
        .animation(.snappy, value: outline.containers.isEmpty)
        .onChange(of: model.placement.placement) { _, _ in model.createProblem = nil }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: isInspector ? 14 : 18) {
            ComposeMark(size: isInspector ? 56 : 72)
            VStack(alignment: .leading, spacing: 6) {
                Text("Docker Compose")
                    .font(.display(isInspector ? .title2 : .title))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(
                    "Your own compose file, run as a service. Coolify keeps its containers, variables, and addresses together."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textCase(nil)
        .foregroundStyle(.primary)
        .padding(.bottom, 18)
        .accessibilityElement(children: .combine)
    }

    private var createBar: some View {
        CreateBar(
            isCreating: model.isCreating,
            status: model.isCreating ? "Creating the service…" : status,
            summary: PlacementSummary.text(model.placement, then: "It stays stopped until you start it."),
            buttonTitle: "Create Service",
            canCreate: model.canCreateFromCompose,
            help: isComposeBlank ? "Write or paste a compose file first" : "Create the service, stopped, and set it up"
        ) {
            Task { await model.createFromCompose() }
        }
    }

    private var isComposeBlank: Bool {
        model.compose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var status: String {
        isComposeBlank ? "Write or paste a compose file" : "Ready to create"
    }
}

#Preview("Written") {
    let placement = PlacementModel(
        servers: [Server(uuid: "s1", name: "localhost", isReachable: true)],
        projects: [Project(uuid: "p1", name: "Website", environments: [Environment(uuid: "e1", name: "production")])],
        placement: Placement(serverUUID: "s1", projectUUID: "p1", environmentUUID: "e1")
    )
    let model = ProvisioningModel(placement: placement)
    model.compose = """
        services:
          web:
            image: nginx:1.27
            environment:
              - SERVICE_URL_WEB_80
          cache:
            image: redis:7
        """
    return NavigationStack {
        ComposeLaunchPad(model: model, instanceRoot: nil)
            .navigationTitle("Docker Compose")
    }
    .frame(width: 760, height: 900)
}

#Preview("Refused") {
    let placement = PlacementModel(
        servers: [Server(uuid: "s1", name: "localhost", isReachable: true)],
        projects: [Project(uuid: "p1", name: "Website", environments: [Environment(uuid: "e1", name: "production")])],
        placement: Placement(serverUUID: "s1", projectUUID: "p1", environmentUUID: "e1")
    )
    let model = ProvisioningModel(placement: placement)
    model.compose = "volumes:\n  data: {}\n"
    model.createProblem = .message(
        "Coolify refused the compose file. Docker Compose file must contain a \"services\" section.")
    return NavigationStack {
        ComposeLaunchPad(model: model, instanceRoot: nil)
    }
    .frame(width: 760, height: 900)
}

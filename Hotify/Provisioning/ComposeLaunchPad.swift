import CoolifyAPI
import SwiftUI

/// A service from a compose file the user writes or pastes: the file, where it goes, and its name. Creating it moves on
/// to the same setup a template gets.
struct ComposeLaunchPad: View {
    var model: ProvisioningModel
    var instanceRoot: URL?

    private var outline: ComposeOutline { ComposeOutline(model.compose) }

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
            Section {
                ComposeEditor(compose: $model.compose, height: Self.editorHeight)
            } header: {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    HStack {
                        Text("Compose File")
                        Spacer(minLength: 12)
                        if model.compose.isEmpty {
                            PasteButton(payloadType: String.self) { strings in
                                guard let text = strings.first else { return }
                                Task { @MainActor in model.compose = text }
                            }
                            .labelStyle(.titleAndIcon)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                        }
                    }
                }
            } footer: {
                Text(
                    "Coolify fills SERVICE_PASSWORD_, SERVICE_USER_, and SERVICE_URL_ variables itself, and asks for the rest after it creates the service. For a compose file in a Git repository, create an application instead."
                )
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
        .safeAreaInset(edge: .bottom, spacing: 0) { createBar }
        .disabled(model.isCreating)
        .animation(.snappy, value: model.createProblem)
        .animation(.snappy, value: model.placement.problem)
        .animation(.snappy, value: outline.containers.isEmpty)
        .onChange(of: model.placement.placement) { _, _ in model.createProblem = nil }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 18) {
            ComposeMark(size: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text("Docker Compose")
                    .font(.display(.title))
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
        HStack(spacing: 14) {
            FlameGlyph(heat: model.isCreating ? .warming : .cold, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.isCreating ? "Creating the service…" : status)
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.interpolate)
                Text(destinationSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Button {
                Task { await model.createFromCompose() }
            } label: {
                Text("Create Service")
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
            .disabled(!model.canCreateFromCompose)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
        .animation(.snappy, value: model.isCreating)
    }

    private var status: String {
        model.compose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Write or paste a compose file" : "Ready to create"
    }

    /// Where the service lands, and that it waits there stopped.
    private var destinationSummary: String {
        let placement = model.placement
        guard let server = placement.server, let project = placement.project, let environment = placement.environment
        else { return "Pick a server, project, and environment." }
        let place = "\(project.name ?? project.uuid) · \(environment.name ?? "")"
        return "On \(server.name), in \(place). It stays stopped until you start it."
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

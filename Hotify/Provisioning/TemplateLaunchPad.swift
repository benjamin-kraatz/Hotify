import CoolifyAPI
import SwiftUI

/// One template, up close: what it is, what it runs, and where it should go. Creating it moves on to setup.
struct TemplateLaunchPad: View {
    var template: ServiceTemplate
    var model: ProvisioningModel
    var instanceRoot: URL?

    private var outline: ComposeOutline { template.outline }

    var body: some View {
        @Bindable var model = model

        Form {
            Section {
                ForEach(outline.containers) { container in
                    ContainerLine(name: container.name, image: container.image)
                }
            } header: {
                hero
            } footer: {
                Text(
                    outline.containers.count == 1
                        ? "One container. Coolify makes its passwords and address when it creates the service."
                        : "\(outline.containers.count) containers, started together. Coolify makes their passwords and addresses when it creates the service."
                )
            }

            PlacementSection(model: model.placement)

            Section {
                TextField("Name", text: $model.name, prompt: Text(verbatim: template.slug))
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
        .onChange(of: model.placement.placement) { _, _ in model.createProblem = nil }
    }

    private var hero: some View {
        heroTitle
            .textCase(nil)
            .padding(.bottom, 14)
    }

    private var heroTitle: some View {
        HStack(alignment: .center, spacing: 18) {
            TemplateLogo(name: template.displayName, url: template.logoURL(instanceRoot: instanceRoot), size: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text(template.displayName)
                    .font(.display(.title))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(template.slogan)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Label(template.shelf.title, systemImage: template.shelf.systemImage)
                        .foregroundStyle(.secondary)
                    if let port = template.port {
                        Text("Port \(port)")
                            .foregroundStyle(.secondary)
                    }
                    if let documentation = template.documentation {
                        Link(destination: documentation) {
                            Label("Documentation", systemImage: "arrow.up.right")
                                .labelStyle(.titleAndIcon)
                        }
                        .foregroundStyle(.ember)
                    }
                }
                .font(.caption.weight(.medium))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var createBar: some View {
        HStack(spacing: 14) {
            FlameGlyph(heat: model.isCreating ? .warming : .cold, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.isCreating ? "Creating \(template.displayName)…" : "Ready to create")
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
                Task { await model.create(template) }
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
            .disabled(!model.canCreate)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
        .animation(.snappy, value: model.isCreating)
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

/// A container a template runs, with its image. Cold, since nothing runs yet.
private struct ContainerLine: View {
    var name: String
    var image: String?

    var body: some View {
        HStack(spacing: 12) {
            FlameGlyph(heat: .cold, height: 16)
            Text(name)
                .fontWeight(.medium)
            Spacer(minLength: 12)
            if let image {
                Text(verbatim: image)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let compose = """
        services:
          ghost:
            image: 'ghost:5'
          mysql:
            image: 'mysql:8.0'
        """
    let placement = PlacementModel(
        servers: [Server(uuid: "s1", name: "localhost", isReachable: true)],
        projects: [Project(uuid: "p1", name: "Website", environments: [Environment(uuid: "e1", name: "production")])],
        placement: Placement(serverUUID: "s1", projectUUID: "p1", environmentUUID: "e1")
    )
    NavigationStack {
        TemplateLaunchPad(
            template: ServiceTemplate(
                slug: "ghost",
                slogan: "Ghost is a content management system (CMS) and blogging platform.",
                category: "cms",
                documentation: URL(string: "https://ghost.org"),
                port: "2368",
                compose: compose
            ),
            model: ProvisioningModel(placement: placement),
            instanceRoot: nil
        )
    }
    .frame(width: 720, height: 760)
}

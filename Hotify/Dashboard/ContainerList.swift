import CoolifyAPI
import SwiftUI

/// The containers inside a service, each with its own status, and start, stop, restart, and edit when it has a uuid.
struct ContainerList: View {
    var containers: [ContainerSummary]
    var client: CoolifyClient?
    var serviceUUID: String?

    @State private var actions = ContainerActions()
    @State private var stopTarget: ContainerSummary?
    @State private var editing: ContainerSummary?
    /// Names and links saved here, until a later poll brings the same values from Coolify.
    @State private var revisions: [String: ContainerRevision] = [:]
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rows: [ContainerSummary] {
        actions.resolved(containers).map { container in
            guard let revision = revisions[container.uuid] else { return container }
            var copy = container
            copy.name = revision.name
            copy.link = revision.link
            return copy
        }
    }

    private var loadID: String {
        guard client != nil, let serviceUUID, !serviceUUID.isEmpty else { return "" }
        return serviceUUID
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let lookupError = actions.lookupError {
                    NoticeBanner(message: lookupError)
                }
                if let actionError = actions.actionError {
                    NoticeBanner(message: actionError)
                }
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.listKey) { index, container in
                        if index > 0 {
                            Divider()
                                .padding(.leading, 46)
                        }
                        ContainerRow(
                            container: container,
                            showsActions: !container.uuid.isEmpty,
                            busyCommand: container.uuid.isEmpty ? nil : actions.command(runningOn: container.uuid),
                            canAct: client != nil && !actions.isBusy,
                            onEdit: { editing = container },
                            onStart: { run(.start, container) },
                            onRestart: { run(.restart, container) },
                            onStop: { stopTarget = container }
                        )
                    }
                }
                .well()
                .heatEdge(isActive: actions.isBusy)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .overlay {
            if containers.isEmpty {
                ContentUnavailableView(
                    "No containers",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("Coolify lists no containers for this service.")
                )
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: rows.map(\.uuid))
        .animation(.snappy, value: actions.lookupError)
        .animation(.snappy, value: actions.actionError)
        .animation(reduceMotion ? nil : .snappy, value: actions.busyUUID)
        .task(id: loadID) {
            revisions = [:]
            actions.reset()
            guard let client, let serviceUUID, !serviceUUID.isEmpty else { return }
            await actions.load(client: client, service: serviceUUID)
        }
        .sheet(item: $editing) { container in
            ContainerEditor(
                container: container,
                values: actions.editorValues(for: container),
                client: client,
                serviceUUID: serviceUUID,
                onSaved: { saved in
                    actions.rememberEdit(container, saved)
                    let link = saved.domains
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .first { !$0.isEmpty }
                        .flatMap(URL.init(string:))
                    revisions[container.uuid] = ContainerRevision(name: saved.name, link: link)
                }
            )
        }
        .confirmationDialog(
            stopTarget.map { "Stop \($0.name)?" } ?? "",
            isPresented: Binding(
                get: { stopTarget != nil },
                set: { isPresented in
                    if !isPresented {
                        stopTarget = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: stopTarget
        ) { container in
            Button("Stop", role: .destructive) {
                run(.stop, container)
            }
        } message: { container in
            Text(
                "Coolify stops \(container.name). The rest of the service keeps running. "
                    + "Volumes and data stay, and you can start it again."
            )
        }
    }

    /// Skips the call when there is no client or no uuid, so a numeric id never reaches the path.
    private func run(_ command: ContainerCommand, _ container: ContainerSummary) {
        guard let client, let serviceUUID, !serviceUUID.isEmpty, !container.uuid.isEmpty else { return }
        Task {
            await actions.run(command, container: container, client: client, service: serviceUUID)
        }
    }
}

/// One container: its flame, name, and image, then only the commands that fit its state. A stopped container offers
/// Start, and a running one Restart and Stop. Every command is also in the row's context menu.
private struct ContainerRow: View {
    var container: ContainerSummary
    var showsActions: Bool
    var busyCommand: ContainerCommand?
    var canAct: Bool
    var onEdit: () -> Void
    var onStart: () -> Void
    var onRestart: () -> Void
    var onStop: () -> Void

    @State private var isHovered = false

    private var heat: Heat { busyCommand == nil ? container.heat : .warming }

    /// Up or on its way, which is what Stop and Restart need. Unknown counts as down, so Start stays reachable.
    private var isUp: Bool { container.heat == .lit || container.heat == .troubled || container.heat == .warming }

    private var statusText: String {
        switch busyCommand {
        case .start: "Starting…"
        case .stop: "Stopping…"
        case .restart: "Restarting…"
        case nil: StatusLabel.text(for: container.status)
        }
    }

    private var portText: String? {
        guard container.isPublic, let port = container.publicPort else { return nil }
        return "Public :\(port)"
    }

    var body: some View {
        HStack(spacing: 14) {
            FlameGlyph(heat: heat, height: 20)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(container.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if container.isDatabase {
                        Chip(text: "Database")
                    }
                    if let portText {
                        Chip(text: portText)
                    }
                }
                if let image = container.image, !image.isEmpty {
                    Text(image)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if let link = container.link {
                Link(destination: link) {
                    Image(systemName: "arrow.up.right.square")
                }
                .foregroundStyle(.secondary)
                .help("Open \(link.host() ?? link.absoluteString)")
                .accessibilityLabel("Open \(link.host() ?? link.absoluteString)")
            }
            Text(statusText)
                .font(.subheadline.weight(busyCommand == nil ? .regular : .semibold))
                .foregroundStyle(heat.needsAttention ? AnyShapeStyle(.glow) : AnyShapeStyle(.secondary))
                .contentTransition(.interpolate)
            if showsActions {
                actionButtons
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.primary.opacity(isHovered ? 0.035 : 0))
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .contextMenu {
            if showsActions {
                Button("Start", systemImage: "play.fill", action: onStart)
                    .disabled(!canAct || isUp)
                Button("Restart", systemImage: "arrow.clockwise", action: onRestart)
                    .disabled(!canAct || !isUp)
                Button("Stop…", systemImage: "stop.fill", action: onStop)
                    .disabled(!canAct || !isUp)
                Divider()
                Button("Edit…", systemImage: "pencil", action: onEdit)
                    .disabled(!canAct)
            }
        }
        .animation(.snappy(duration: 0.15), value: isHovered)
        .animation(.snappy, value: heat)
        .animation(.snappy, value: statusText)
        .animation(.snappy, value: isUp)
        .accessibilityElement(children: showsActions ? .contain : .combine)
    }

    private var actionButtons: some View {
        HStack(spacing: 2) {
            if busyCommand == nil {
                if isUp {
                    commandButton(
                        "Restart", systemImage: "arrow.clockwise", help: "Restart this container", action: onRestart)
                    commandButton(
                        "Stop", systemImage: "stop.fill", help: "Stop this container. Volumes and data stay.",
                        action: onStop)
                } else {
                    commandButton("Start", systemImage: "play.fill", help: "Start this container", action: onStart)
                }
            }
            commandButton("Edit", systemImage: "pencil", help: "Edit this container", action: onEdit)
        }
        .disabled(!canAct)
        .controlSize(.small)
    }

    private func commandButton(
        _ title: String,
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(width: 24, height: 24)
            .contentShape(.rect)
            .help(help)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
}

private struct ContainerRevision: Hashable {
    var name: String
    var link: URL?
}

extension ContainerSummary {
    /// Stable across a status change, and distinct when an application and a database share a numeric id.
    fileprivate var listKey: String {
        let role = isDatabase ? "database" : "application"
        let name = serviceName.isEmpty ? self.name : serviceName
        return "\(role)-\(id)-\(name)"
    }
}

#Preview {
    ContainerList(containers: [
        ContainerSummary(
            id: 1,
            name: "dashboard",
            status: "running:healthy",
            image: "ghcr.io/get-convex/convex-dashboard:latest",
            link: URL(string: "https://convex.example.com")
        ),
        ContainerSummary(
            id: 2, name: "backend", status: "running:unhealthy", image: "ghcr.io/get-convex/convex-backend"),
        ContainerSummary(id: 3, name: "token-generator", status: "exited"),
    ])
    .frame(width: 480, height: 320)
}

#Preview("Application and database") {
    ContainerList(containers: [
        ContainerSummary(
            id: 1,
            name: "dashboard",
            serviceName: "dashboard",
            status: "running:healthy",
            image: "ghcr.io/get-convex/convex-dashboard:latest",
            link: URL(string: "https://convex.example.com"),
            uuid: "app-1",
            fqdn: "https://convex.example.com,https://www.convex.example.com"
        ),
        ContainerSummary(
            id: -2,
            name: "postgres",
            serviceName: "postgres",
            status: "running:healthy",
            image: "postgres:16-alpine",
            uuid: "db-1",
            isDatabase: true,
            isPublic: true,
            publicPort: 5432
        ),
    ])
    .frame(width: 560, height: 240)
}

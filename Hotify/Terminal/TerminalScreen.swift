import CoolifyAPI
import SwiftUI

/// A shell in one of a resource's containers, over SSH from this device, with the steps that lead there.
struct TerminalScreen: View {
    @State private var model: TerminalModel
    @State private var editsAddress = false
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(client: CoolifyClient?, target: TerminalTarget) {
        _model = State(initialValue: TerminalModel(client: client, target: target))
    }

    /// For previews: a screen at a given step, with nothing behind it.
    init(model: TerminalModel) {
        _model = State(initialValue: model)
    }

    private var heading: String {
        if let container = model.container {
            return TerminalModel.title(of: container, target: model.target)
        }
        return model.target.containerTitle ?? model.target.resourceName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 12)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        }
        .animation(reduceMotion ? nil : .snappy, value: model.phase)
        .animation(reduceMotion ? nil : .snappy, value: model.ending)
        .task { await model.start() }
        .onDisappear { model.stop() }
        .sheet(isPresented: $editsAddress) {
            if let server = model.server {
                AddressSheet(serverName: server.name, current: model.address, hasOverride: model.hasOverride) {
                    address in
                    Task { await model.setAddress(address) }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "apple.terminal")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(heading)
                    .font(.headline)
                    .lineLimit(1)
                if let server = model.server {
                    Text(model.destination.map { "\(server.name) · \($0)" } ?? server.name)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if model.server != nil, model.address != nil || model.offersAddress {
                Button("SSH Address…", systemImage: "network") { editsAddress = true }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Change the address this device connects to")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .locating:
            progress("Finding the server…")
        case .unlocking:
            progress("Waiting for \(UnlockMethod.current().title)…")
        case .connecting:
            progress(model.server.map { "Connecting to \($0.name)…" } ?? "Connecting…")
        case .unavailable(let message):
            ContentUnavailableView {
                Label("No Terminal Here", systemImage: "apple.terminal")
            } description: {
                Text(message)
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("No Connection", systemImage: "bolt.horizontal")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await model.connect() } }
                    .buttonStyle(.borderedProminent)
                if model.offersAddress, model.server != nil {
                    Button("Change the Address…") { editsAddress = true }
                }
            }
        case .trustHost(let key, let previous):
            scrolling {
                HostKeyCard(
                    serverName: model.server?.name ?? "The server",
                    presented: key,
                    previous: previous,
                    onTrust: { Task { await model.trustPresentedKey() } },
                    onRetry: { Task { await model.connect() } }
                )
            }
        case .needsKey:
            scrolling {
                KeySetupCard(
                    serverName: model.server?.name ?? "the server",
                    user: model.server?.sshUser ?? "root",
                    publicKeyLine: model.publicKeyLine ?? "",
                    canInstall: model.canInstall,
                    isInstalling: model.isInstalling,
                    problem: model.installProblem,
                    onInstall: { Task { await model.installDeviceKey() } },
                    onConnect: { Task { await model.connect() } }
                )
            }
        case .choosing(let containers):
            scrolling {
                ContainerPicker(containers: containers, target: model.target) { container in
                    Task { await model.open(container) }
                }
            }
        case .running:
            TerminalCanvas(model: model)
                .id(model.session)
                .padding(.leading, 8)
                .padding(.top, 4)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let ending = model.ending {
                        endedBar(ending)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
        }
    }

    private func endedBar(_ message: String) -> some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Reconnect") { Task { await model.connect() } }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func progress(_ text: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(text)
                .foregroundStyle(.secondary)
        }
    }

    private func scrolling(@ViewBuilder _ content: () -> some View) -> some View {
        ScrollView {
            content()
                .padding(20)
                .frame(maxWidth: .infinity)
        }
    }
}

#Preview("Key setup") {
    TerminalScreen(
        model: TerminalModel(
            previewing: TerminalTarget(route: .application("app"), resourceName: "marketing-site"),
            phase: .needsKey,
            server: Server(uuid: "s1", name: "edge-1", ip: "203.0.113.9"),
            publicKeyLine: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOmN7m8zq3vVQ7Uu7d0P0hS3cY1x0b1Yl6r1oZb0yWkK hotify-Mac"
        )
    )
    .frame(width: 640, height: 560)
}

#Preview("Tunnel") {
    TerminalScreen(
        model: TerminalModel(
            previewing: TerminalTarget(route: .database("db"), resourceName: "postgres"),
            phase: .unavailable("Terminal doesn't support servers behind a Cloudflare Tunnel yet."),
            server: Server(uuid: "s1", name: "home-lab", ip: "ssh.example.com")
        )
    )
    .frame(width: 640, height: 400)
}

#Preview("Unreachable") {
    TerminalScreen(
        model: TerminalModel(
            previewing: TerminalTarget(route: .database("db"), resourceName: "postgres"),
            phase: .failed("Hotify couldn't reach edge-1 at 203.0.113.9:22."),
            server: Server(uuid: "s1", name: "edge-1", ip: "203.0.113.9")
        )
    )
    .frame(width: 640, height: 400)
}

import CoolifyAPI
import SwiftUI

/// A shell in one of a resource's containers, over SSH from this device, with the steps that lead there.
///
/// Once a shell has run, the canvas stays through a reconnect, so the earlier output sits above the divider the
/// model prints. The chrome around it follows the terminal's theme, not the app's appearance.
struct TerminalScreen: View {
    @State private var model: TerminalModel
    @State private var surface = TerminalSurface()
    @State private var editsAddress = false
    @State private var bellFlash = false
    /// Whether a shell was running when the app went to the background, on iOS.
    @State private var leftWhileRunning = false
    @AppStorage(TerminalPreferences.fontSizeKey) private var fontSize = TerminalPreferences.defaultFontSize
    @AppStorage(TerminalPreferences.themeKey) private var theme = TerminalTheme.ember
    @AppStorage(TerminalPreferences.optionAsMetaKey) private var optionAsMeta = false
    @AppStorage(TerminalPreferences.confirmsPasteKey) private var confirmsPaste = true
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SwiftUI.Environment(\.colorScheme) private var colorScheme
    @SwiftUI.Environment(\.scenePhase) private var scenePhase

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

    private var palette: TerminalPalette { theme.palette(for: colorScheme) }

    /// Once a shell has run, a reconnect happens over the canvas rather than in place of it.
    private var showsCanvas: Bool {
        switch model.phase {
        case .running: true
        case .unlocking, .connecting: model.session > 0
        default: false
        }
    }

    private var isReconnecting: Bool {
        showsCanvas && model.phase != .running
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TerminalHeader(
                heading: heading,
                serverName: model.server?.name,
                destination: model.destination,
                heat: model.linkHeat,
                linkLabel: model.linkLabel,
                latency: model.latency,
                title: surface.title,
                directory: surface.directory,
                showsActions: showsCanvas,
                offersAddress: model.server != nil && (model.address != nil || model.offersAddress),
                onRun: { surface.run($0.command) },
                onFind: { surface.findTerm = surface.findTerm ?? "" },
                onZoom: zoom,
                onClear: surface.clearScrollback,
                onAddress: { editsAddress = true }
            )
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
        .animation(reduceMotion ? nil : .snappy, value: surface.findTerm == nil)
        .task { await model.start() }
        .onDisappear { model.stop() }
        .focusedSceneValue(
            \.terminalActions, showsCanvas ? TerminalActions(zoom: zoom, clear: surface.clearScrollback) : nil
        )
        .sheet(isPresented: $editsAddress) {
            if let server = model.server {
                AddressSheet(serverName: server.name, current: model.address, hasOverride: model.hasOverride) {
                    address in
                    Task { await model.setAddress(address) }
                }
            }
        }
        .alert(
            surface.pendingPaste?.question ?? "",
            isPresented: Binding(
                get: { surface.pendingPaste != nil },
                set: { if !$0 { surface.pendingPaste = nil } }
            ),
            presenting: surface.pendingPaste
        ) { check in
            Button("Paste") {
                surface.paste(check.text, checked: false)
                surface.focus()
            }
            Button("Cancel", role: .cancel) {
                surface.focus()
            }
        } message: { check in
            Text(check.explanation)
        }
        .sensoryFeedback(.warning, trigger: surface.bells)
        .task(id: surface.bells) {
            guard surface.bells > 0 else { return }
            withAnimation(.easeOut(duration: 0.08)) { bellFlash = true }
            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(.easeIn(duration: 0.35)) { bellFlash = false }
        }
        #if os(iOS)
        // iOS cuts the socket while the app sleeps. Coming back to the terminal picks the shell up again.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                leftWhileRunning = model.phase == .running && model.ending == nil
            case .active:
                guard leftWhileRunning else { return }
                leftWhileRunning = false
                Task { await model.resumeAfterBackground() }
            default:
                break
            }
        }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if showsCanvas {
            canvas
        } else {
            switch model.phase {
            case .locating:
                progress("Finding the server…")
            case .unlocking:
                progress("Waiting for \(UnlockMethod.current().title)…")
            case .connecting, .running:
                progress(model.server.map { "Connecting to \($0.name)…" } ?? "Connecting…")
            case .unavailable(let message):
                ContentUnavailableView {
                    Label {
                        Text("No Terminal Here")
                    } icon: {
                        FlameGlyph(heat: .cold, height: 40)
                    }
                } description: {
                    Text(message)
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label {
                        Text("No Connection")
                    } icon: {
                        FlameGlyph(heat: .troubled, height: 40)
                    }
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
            }
        }
    }

    /// The canvas in its palette, with the search bar above it and the session's end below it. The chrome inside
    /// takes the palette's lightness, so a dark terminal in a light app keeps dark bars.
    private var canvas: some View {
        TerminalCanvas(
            model: model,
            surface: surface,
            palette: palette,
            fontSize: fontSize,
            optionAsMeta: optionAsMeta,
            confirmsPaste: confirmsPaste,
            onFontSizeChange: { fontSize = $0 }
        )
        .padding(.leading, 10)
        .padding(.top, 8)
        .background(Color(rgb: palette.background))
        .overlay {
            Rectangle()
                .fill(.glow.opacity(bellFlash ? 0.28 : 0))
                .allowsHitTesting(false)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if surface.findTerm != nil {
                FindBar(
                    term: Binding(get: { surface.findTerm ?? "" }, set: { surface.findTerm = $0 }),
                    matches: surface.matches,
                    onFind: { forward in surface.find(surface.findTerm ?? "", forward: forward) },
                    onClose: surface.closeFind
                )
                .onChange(of: surface.findTerm) { _, term in
                    surface.find(term ?? "")
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isReconnecting {
                reconnectingBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let ending = model.ending {
                endedBar(ending)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environment(\.colorScheme, palette.isDark ? .dark : .light)
        #if os(macOS)
        .clipShape(.rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
            .strokeBorder(.primary.opacity(0.1), lineWidth: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
        #endif
    }

    private func endedBar(_ message: String) -> some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Reconnect") { Task { await model.connect() } }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var reconnectingBar: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(
                model.phase == .unlocking
                    ? "Waiting for \(UnlockMethod.current().title)…"
                    : "Reconnecting to \(model.server?.name ?? "the server")…"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            Spacer(minLength: 8)
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

    private func zoom(_ step: TerminalZoom) {
        switch step {
        case .bigger: fontSize = TerminalPreferences.clamp(fontSize + TerminalPreferences.fontStep)
        case .smaller: fontSize = TerminalPreferences.clamp(fontSize - TerminalPreferences.fontStep)
        case .reset: fontSize = TerminalPreferences.defaultFontSize
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

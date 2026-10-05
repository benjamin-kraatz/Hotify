import CoolifyAPI
import SwiftUI

/// One server in the detail column: validate it, prune Docker, restart the proxy, and read its domains.
struct ServerDetailScreen: View {
    var client: CoolifyClient?
    var server: ServerLine
    var back: DetailBack

    @State private var model = ServerPageModel()
    @State private var prompt: ServerPrompt?
    @State private var refreshes = 0
    /// Shared variables replace the overview in this column. Back returns here, without a new route.
    @State private var showsVariables = false
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if showsVariables {
                SharedVariableScreen(
                    client: client,
                    scope: .server(server.id),
                    sectionTitle: server.name,
                    navigationTitle: "Server Variables",
                    back: DetailBack(title: server.name) { showsVariables = false }
                )
            } else {
                overview
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: showsVariables)
    }

    private var overview: some View {
        ServerDetail(
            server: server,
            model: model,
            canAct: client != nil,
            client: client,
            onValidate: { Task { await validate(install: false) } },
            onInstall: { prompt = .install },
            onSaveCleanup: { Task { await saveCleanup() } },
            onRunCleanup: askToCleanUp,
            onRestartProxy: { prompt = .restartProxy },
            onRetry: { Task { await reload() } },
            onShowVariables: { showsVariables = true }
        )
        .navigationTitle("Server")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .replacesSystemBack(true)
        .toolbar {
            DetailNavigation(title: "Server", back: back)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    refreshes += 1
                    Task { await reload() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .symbolEffect(.rotate, value: refreshes)
                }
                .disabled(client == nil)
                .help("Refresh this server")
            }
        }
        .task(id: server.id) { await follow() }
        .refreshable { await reload() }
        .confirmationDialog(
            prompt?.title(for: server.name) ?? "",
            isPresented: Binding(
                get: { prompt != nil },
                set: { isPresented in
                    if !isPresented { prompt = nil }
                }
            ),
            titleVisibility: .visible,
            presenting: prompt
        ) { prompt in
            Button(prompt.confirmTitle, role: .destructive) {
                Task { await confirm(prompt) }
            }
        } message: { prompt in
            Text(prompt.message)
        }
    }

    private func follow() async {
        model.prepare(for: server.id)
        guard let client else { return }
        while !Task.isCancelled {
            if !model.isBusy {
                await model.refresh(client: client, server: server.id)
            }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
        }
    }

    private func reload() async {
        guard let client else { return }
        await model.refresh(client: client, server: server.id)
    }

    private func validate(install: Bool) async {
        guard let client else { return }
        await model.validate(client: client, server: server.id, install: install)
    }

    private func saveCleanup() async {
        guard let client else { return }
        await model.saveCleanup(client: client, server: server.id)
    }

    private func askToCleanUp() {
        let volumes = model.draft?.deleteUnusedVolumes == true
        let networks = model.draft?.deleteUnusedNetworks == true
        if volumes || networks {
            prompt = .cleanup(volumes: volumes, networks: networks)
        } else {
            Task { await runCleanup() }
        }
    }

    private func runCleanup() async {
        guard let client else { return }
        await model.runCleanup(client: client, server: server.id)
    }

    private func confirm(_ prompt: ServerPrompt) async {
        switch prompt {
        case .install:
            await validate(install: true)
        case .cleanup:
            await runCleanup()
        case .restartProxy:
            guard let client else { return }
            await model.restartProxy(client: client, server: server.id)
        }
    }
}

/// The server page's layout. Takes the loaded model, so a preview does not need a connection.
struct ServerDetail: View {
    var server: ServerLine
    var model: ServerPageModel
    var canAct: Bool
    var client: CoolifyClient? = nil
    var onValidate: () -> Void = {}
    var onInstall: () -> Void = {}
    var onSaveCleanup: () -> Void = {}
    var onRunCleanup: () -> Void = {}
    var onRestartProxy: () -> Void = {}
    var onRetry: () -> Void = {}
    /// Swaps this page for the server's shared variables.
    var onShowVariables: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                header
                actions
                sharedVariables
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 8)

            notices

            Form {
                if model.hasLoaded {
                    DockerCleanupSection(
                        model: model,
                        canAct: canAct,
                        onSave: onSaveCleanup,
                        onRun: onRunCleanup
                    )
                    ServerProxySection(
                        proxy: model.proxy,
                        canAct: canAct,
                        isBusy: model.isBusy,
                        isRestarting: model.write == .restartProxy,
                        onRestart: onRestartProxy
                    )
                    CloudflareTunnelSection(client: client, serverUUID: server.id, canAct: canAct)
                    ServerDomainList(groups: model.domains)
                } else if model.error != nil {
                    Section {
                        Button("Try Again", action: onRetry)
                            .glassButton()
                    }
                } else if canAct {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                } else {
                    Section {
                        Text("Hotify is not connected to this instance.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .animation(.snappy, value: model.error)
        .animation(.snappy, value: model.notice)
        .animation(.snappy, value: model.hasLoaded)
        .animation(.snappy, value: model.write)
    }

    private var heat: Heat {
        switch server.isReachable {
        case true: .lit
        case false: .troubled
        default: .unknown
        }
    }

    private var reachability: String {
        switch server.isReachable {
        case true: "Reachable"
        case false: "Unreachable"
        default: "Unknown"
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            FlameGlyph(heat: heat, height: 56, ignitesOnAppear: true, breathes: true)
            VStack(alignment: .leading, spacing: 5) {
                Text(server.name)
                    .font(.display(.title))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .textSelection(.enabled)
                Text(reachability)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(heat == .troubled ? AnyShapeStyle(.glow) : AnyShapeStyle(.secondary))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: onValidate) {
                Label(model.write == .validate ? "Validating…" : "Validate", systemImage: "checkmark.circle")
            }
            .glassButton(prominent: true)
            .disabled(!canAct || model.isBusy)
            .help("Checks that Coolify can reach this server.")

            Button(action: onInstall) {
                Label(
                    model.write == .install ? "Installing…" : "Install Prerequisites",
                    systemImage: "arrow.down.circle"
                )
            }
            .glassButton()
            .disabled(!canAct || model.isBusy)
            .help("Installs missing prerequisites and can restart Docker.")
        }
    }

    private var sharedVariables: some View {
        Button(action: onShowVariables) {
            HStack(spacing: 8) {
                Label("Shared Variables", systemImage: "curlybraces")
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.plain)
        .help("Variables every resource on \(server.name) can use, as {{server.KEY}}.")
        .accessibilityHint("Shows this server's shared variables")
    }

    @ViewBuilder
    private var notices: some View {
        VStack(spacing: 8) {
            if let error = model.error {
                NoticeBanner(message: error)
            }
            if let notice = model.notice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.ember)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ember.opacity(0.12), in: .rect(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, model.error == nil && model.notice == nil ? 0 : 12)
    }
}

/// A confirmed server action. Destructive so Return does not confirm it on the Mac.
private enum ServerPrompt: Identifiable {
    case install
    case cleanup(volumes: Bool, networks: Bool)
    case restartProxy

    var id: String {
        switch self {
        case .install: "install"
        case .cleanup: "cleanup"
        case .restartProxy: "restart"
        }
    }

    func title(for name: String) -> String {
        switch self {
        case .install: "Install prerequisites on \(name)?"
        case .cleanup: "Clean up Docker on \(name)?"
        case .restartProxy: "Restart the proxy on \(name)?"
        }
    }

    var confirmTitle: String {
        switch self {
        case .install: "Install Prerequisites"
        case .cleanup: "Clean Up"
        case .restartProxy: "Restart Proxy"
        }
    }

    var message: String {
        switch self {
        case .install:
            "This can install prerequisites and restart Docker."
        case .cleanup(let volumes, let networks):
            switch (volumes, networks) {
            case (true, true): "This run deletes unused volumes and unused networks."
            case (true, false): "This run deletes unused volumes."
            case (false, true): "This run deletes unused networks."
            case (false, false): "Coolify prunes unused Docker data."
            }
        case .restartProxy:
            "Every domain on this server drops until the proxy is back."
        }
    }
}

#Preview("Screen") {
    NavigationStack {
        ServerDetailScreen(
            client: nil,
            server: ServerLine(id: "localhost", name: "localhost", isReachable: true),
            back: DetailBack(title: "Dashboard") {}
        )
    }
    .frame(width: 640, height: 760)
}

#Preview("Reachable") {
    NavigationStack {
        ServerDetail(server: ServerLine(id: "localhost", name: "localhost", isReachable: true), model: .sample)
    }
    .frame(width: 640, height: 760)
}

#Preview("Unreachable") {
    NavigationStack {
        ServerDetail(server: ServerLine(id: "build", name: "build-1", isReachable: false), model: .sample)
    }
    .frame(width: 640, height: 760)
}

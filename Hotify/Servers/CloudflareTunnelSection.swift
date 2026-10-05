import CoolifyAPI
import SwiftUI

/// Records that a server is reached through a Cloudflare Tunnel.
///
/// The section loads its own model. The API does not install or remove cloudflared.
struct CloudflareTunnelSection: View {
    var client: CoolifyClient?
    var serverUUID: String
    var canAct: Bool

    @State private var model: CloudflareTunnelModel
    @State private var confirmDisable = false
    private let loadsFromNetwork: Bool
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(client: CoolifyClient? = nil, serverUUID: String, canAct: Bool, preview: CloudflareTunnel? = nil) {
        self.client = client
        self.serverUUID = serverUUID
        self.canAct = canAct
        let model = CloudflareTunnelModel()
        if let preview {
            model.present(preview)
        }
        _model = State(initialValue: model)
        loadsFromNetwork = preview == nil
    }

    var body: some View {
        Section {
            if model.hasLoaded, let tunnel = model.tunnel {
                LabeledContent("Current IP") {
                    Text(address(tunnel.ip))
                        .font(.body.monospaced())
                        .foregroundStyle(isOn ? AnyShapeStyle(.core) : AnyShapeStyle(.primary))
                        .textSelection(.enabled)
                }
                if let previous = tunnel.ipPrevious?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !previous.isEmpty
                {
                    LabeledContent("Previous IP") {
                        Text(previous)
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                Toggle(isOn: tunnelSwitch) {
                    Text("Cloudflare Tunnel")
                        .foregroundStyle(isOn ? AnyShapeStyle(.ember) : AnyShapeStyle(.primary))
                }
                .disabled(!canAct || model.isUpdating || client == nil)
                .help("Marks this server as reached through a Cloudflare Tunnel. Does not install cloudflared.")
                if let error = model.error {
                    Text(error)
                        .foregroundStyle(.glow)
                        .textSelection(.enabled)
                }
            } else if let error = model.error {
                Text(error)
                    .foregroundStyle(.glow)
                    .textSelection(.enabled)
                Button("Try Again") {
                    Task { await model.load(client: client, server: serverUUID) }
                }
                .disabled(client == nil)
            } else if client != nil {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else {
                Text("Hotify is not connected to this instance.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Cloudflare Tunnel")
        } footer: {
            Text(
                "The API does not install or remove cloudflared. "
                    + "Turning this on only marks the server as reached through a tunnel."
            )
        }
        .confirmationDialog(
            "Turn off the Cloudflare Tunnel?",
            isPresented: $confirmDisable,
            titleVisibility: .visible
        ) {
            Button("Turn Off") {
                guard let client else { return }
                Task { await model.disable(client: client, server: serverUUID) }
            }
        } message: {
            Text(
                "The remote cloudflared container is left in place, "
                    + "and the previous IP is restored when Coolify still has it."
            )
        }
        .task(id: serverUUID) {
            guard loadsFromNetwork else { return }
            await model.load(client: client, server: serverUUID)
        }
        .animation(reduceMotion ? nil : .snappy, value: model.tunnel)
    }

    private var isOn: Bool {
        model.tunnel?.isCloudflareTunnel == true
    }

    private var tunnelSwitch: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { wantsOn in
                guard let client, canAct, !model.isUpdating else { return }
                if wantsOn {
                    Task { await model.enable(client: client, server: serverUUID) }
                } else {
                    confirmDisable = true
                }
            }
        )
    }

    private func address(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unknown" : trimmed
    }
}

#Preview("On") {
    NavigationStack {
        Form {
            CloudflareTunnelSection(
                serverUUID: "build-1",
                canAct: true,
                preview: CloudflareTunnel(
                    ip: "10.0.0.8", ipPrevious: "203.0.113.10", isCloudflareTunnel: true)
            )
        }
    }
    .frame(width: 480, height: 320)
}

#Preview("Off") {
    NavigationStack {
        Form {
            CloudflareTunnelSection(
                serverUUID: "build-1",
                canAct: true,
                preview: CloudflareTunnel(ip: "203.0.113.10", ipPrevious: nil, isCloudflareTunnel: false)
            )
        }
    }
    .frame(width: 480, height: 280)
}

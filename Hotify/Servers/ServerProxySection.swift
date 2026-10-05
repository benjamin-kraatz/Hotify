import CoolifyAPI
import SwiftUI

/// The proxy's type and status, and the button that restarts it.
struct ServerProxySection: View {
    var proxy: ServerProxy?
    var canAct: Bool
    var isBusy: Bool
    var isRestarting: Bool
    var onRestart: () -> Void

    private var heat: Heat {
        switch proxy?.status?.lowercased() {
        case "failed", "error": .troubled
        default: Heat(status: proxy?.status)
        }
    }

    private var typeLabel: String {
        switch proxy?.proxyType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "traefik": "Traefik"
        case "caddy": "Caddy"
        case "nginx": "NGINX"
        case "none": "None"
        case let value? where !value.isEmpty:
            value.prefix(1).uppercased() + value.dropFirst()
        default:
            "Unknown"
        }
    }

    private var redirectLabel: String {
        if proxy?.redirectEnabled == true {
            if let url = proxy?.redirectUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
                return url
            }
            return "On"
        }
        if proxy?.redirectEnabled == false {
            return "Off"
        }
        return "Unknown"
    }

    var body: some View {
        Section {
            LabeledContent("Type", value: typeLabel)
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    FlameGlyph(heat: heat, height: 12)
                    Text(StatusLabel.text(for: proxy?.status))
                        .foregroundStyle(heat.needsAttention ? AnyShapeStyle(.glow) : AnyShapeStyle(.primary))
                }
            }
            LabeledContent("Redirect", value: redirectLabel)
            Button(action: onRestart) {
                Label(isRestarting ? "Restarting…" : "Restart Proxy", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!canAct || isBusy)
            .help("Every domain on this server drops until the proxy is back.")
        } header: {
            Text("Proxy")
        } footer: {
            Text("Restarting the proxy drops every domain on this server until it is back.")
        }
    }
}

#Preview {
    NavigationStack {
        Form {
            ServerProxySection(
                proxy: ServerProxy(
                    status: "running", proxyType: "traefik", redirectEnabled: false, redirectUrl: nil),
                canAct: true,
                isBusy: false,
                isRestarting: false,
                onRestart: {}
            )
        }
    }
    .frame(width: 480, height: 280)
}

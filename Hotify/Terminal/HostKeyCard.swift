import HotifySSH
import SwiftUI

/// Asks whether to trust the key a server presented: the first time, or because it changed.
struct HostKeyCard: View {
    var serverName: String
    var presented: SSHHostKey
    /// The key trusted before, when this one replaces it.
    var previous: SSHHostKey?
    var onTrust: () -> Void
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                previous == nil ? "Trust \(serverName)?" : "\(serverName)'s key changed",
                systemImage: previous == nil ? "checkmark.shield" : "exclamationmark.shield"
            )
            .font(.headline)
            .foregroundStyle(previous == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.glow))

            Text(explanation)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                fingerprint(previous == nil ? presented.algorithm : "Now", presented)
                if let previous {
                    fingerprint("Before", previous)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .well(cornerRadius: 10)

            Text("To compare, run `ssh-keygen -lf /etc/ssh/ssh_host_\(keyFile)_key.pub` on the server.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack {
                if previous == nil {
                    Button("Trust and Connect", action: onTrust)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Try Again", action: onRetry)
                        .buttonStyle(.borderedProminent)
                    Button("Trust the New Key", action: onTrust)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: 520, alignment: .leading)
        .well()
    }

    private var explanation: String {
        if previous == nil {
            return "This is the first time Hotify connects to \(serverName). Check that the fingerprint below is the "
                + "server's before you trust it. Hotify remembers it and warns you if it ever changes."
        }
        return "\(serverName) presented a different key than last time. That happens after the server is reinstalled, "
            + "or when something sits between this device and the server. Only trust the new key if you know why "
            + "it changed."
    }

    /// `ssh-ed25519` keeps its key in `ssh_host_ed25519_key.pub`.
    private var keyFile: String {
        switch presented.algorithm {
        case "ssh-ed25519": "ed25519"
        case "ssh-rsa": "rsa"
        default: presented.algorithm.hasPrefix("ecdsa") ? "ecdsa" : "ed25519"
        }
    }

    private func fingerprint(_ label: String, _ key: SSHHostKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(key.fingerprint)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }
}

#Preview("First contact") {
    HostKeyCard(
        serverName: "edge-1",
        presented: SSHHostKey(
            openSSH: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOmN7m8zq3vVQ7Uu7d0P0hS3cY1x0b1Yl6r1oZb0yWkK"),
        onTrust: {},
        onRetry: {}
    )
    .padding()
}

#Preview("Changed") {
    HostKeyCard(
        serverName: "edge-1",
        presented: SSHHostKey(
            openSSH: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOmN7m8zq3vVQ7Uu7d0P0hS3cY1x0b1Yl6r1oZb0yWkK"),
        previous: SSHHostKey(
            openSSH: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA2xq0wqM9oW4gq0hYk1mJ7lV2Nn9l8sP4kV3uQe8fGz"),
        onTrust: {},
        onRetry: {}
    )
    .padding()
}

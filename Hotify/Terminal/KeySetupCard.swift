import CoolifyAPI
import SwiftUI

/// Gets this device's key onto a server that turned it down: with Coolify's key in one step, or by hand.
struct KeySetupCard: View {
    var serverName: String
    var user: String
    var publicKeyLine: String
    var canInstall: Bool
    var isInstalling: Bool
    var problem: String?
    var onInstall: () -> Void
    var onConnect: () -> Void

    @State private var copies = 0

    private var command: String { TerminalCommand.addKeyByHand(publicKeyLine) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Add this \(UnlockMethod.deviceName)'s key to \(serverName)", systemImage: "key")
                    .font(.headline)
                Text(
                    "Hotify signs in to your servers with a key of its own, kept on this \(UnlockMethod.deviceName). "
                        + "\(serverName) doesn't accept it yet."
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let problem {
                NoticeBanner(message: problem)
            }

            if canInstall {
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: onInstall) {
                        HStack(spacing: 8) {
                            if isInstalling {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isInstalling ? "Adding the Key…" : "Add It with Coolify's Key")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isInstalling)
                    Text(
                        "Hotify signs in once with the key Coolify uses for \(serverName), adds this "
                            + "\(UnlockMethod.deviceName)'s key for \(user), and forgets Coolify's key again."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(canInstall ? "Or run this on \(serverName) as \(user):" : "Run this on \(serverName) as \(user):")
                    .font(.callout)
                Text(command)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .well(cornerRadius: 8)
                HStack {
                    Button("Copy Command", systemImage: "doc.on.doc") { copy(command) }
                    Button("Copy Key") { copy(publicKeyLine) }
                    Spacer()
                    Button("Connect", action: onConnect)
                        .disabled(isInstalling)
                }
                .sensoryFeedback(.success, trigger: copies)
            }
        }
        .padding(18)
        .frame(maxWidth: 560, alignment: .leading)
        .well()
        .animation(.snappy, value: problem)
    }

    private func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        copies += 1
    }
}

#Preview {
    KeySetupCard(
        serverName: "edge-1",
        user: "root",
        publicKeyLine: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOmN7m8zq3vVQ7Uu7d0P0hS3cY1x0b1Yl6r1oZb0yWkK hotify-Mac",
        canInstall: true,
        isInstalling: false,
        problem: nil,
        onInstall: {},
        onConnect: {}
    )
    .padding()
}

#Preview("By hand only") {
    KeySetupCard(
        serverName: "edge-1",
        user: "deploy",
        publicKeyLine: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOmN7m8zq3vVQ7Uu7d0P0hS3cY1x0b1Yl6r1oZb0yWkK hotify-Mac",
        canInstall: true,
        isInstalling: false,
        problem: "Coolify didn't share its key with this API token. Add the key by hand, or use a token with the "
            + "read:sensitive permission.",
        onInstall: {},
        onConnect: {}
    )
    .padding()
}

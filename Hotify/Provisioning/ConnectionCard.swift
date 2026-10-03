import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// How to reach a new database. Each address holds the password Coolify made, so it stays masked until the variable
/// lock opens, and copying asks the same.
struct ConnectionCard: View {
    var internalURL: String?
    var externalURL: String?

    /// Missing in previews, which show the addresses as they are.
    @SwiftUI.Environment(VariableLock.self) private var lock: VariableLock?
    @State private var copied: String?

    private var isOpen: Bool { lock?.isOpen ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Connect", systemImage: "link")
                .font(.headline)
            if let internalURL {
                row("From the server's network", internalURL)
            }
            if let externalURL {
                row("From anywhere", externalURL)
            }
            Text("The database's settings in Coolify keep these too.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .well()
        .animation(.snappy, value: isOpen)
    }

    private func row(_ title: String, _ address: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Text(verbatim: isOpen ? address : Self.masked(address))
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .contentTransition(.interpolate)
                Spacer(minLength: 8)
                if !isOpen {
                    Button("Show", systemImage: "eye") {
                        Task { await lock?.unlock() }
                    }
                    .labelStyle(.iconOnly)
                    .help("Show the password")
                }
                Button(
                    copied == address ? "Copied" : "Copy", systemImage: copied == address ? "checkmark" : "doc.on.doc"
                ) {
                    Task { await copy(address) }
                }
                .labelStyle(.iconOnly)
                .help("Copy the address with its password")
            }
            .buttonStyle(.borderless)
        }
    }

    private func copy(_ address: String) async {
        if !isOpen, let lock {
            guard await lock.unlock() else { return }
        }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
        #else
        UIPasteboard.general.string = address
        #endif
        copied = address
    }

    /// The address with its password covered, so its shape still shows.
    static func masked(_ address: String) -> String {
        guard var components = URLComponents(string: address), components.password != nil else {
            return String(repeating: "•", count: 12)
        }
        components.password = "••••••"
        return components.string ?? String(repeating: "•", count: 12)
    }
}

#Preview {
    ConnectionCard(
        internalURL: "postgres://postgres:secret@q8w2c4:5432/postgres",
        externalURL: "postgres://postgres:secret@203.0.113.7:5433/postgres"
    )
    .padding()
    .frame(width: 520)
}

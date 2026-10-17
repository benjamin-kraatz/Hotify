import CoolifyAPI
import SwiftUI

/// The SSH address this device uses for a server, in place of the one Coolify reports.
struct AddressSheet: View {
    var serverName: String
    var current: SSHAddress?
    var hasOverride: Bool
    var onSave: (SSHAddress?) -> Void

    @SwiftUI.Environment(\.dismiss) private var dismiss
    @State private var host: String
    @State private var port: String

    init(serverName: String, current: SSHAddress?, hasOverride: Bool, onSave: @escaping (SSHAddress?) -> Void) {
        self.serverName = serverName
        self.current = current
        self.hasOverride = hasOverride
        self.onSave = onSave
        _host = State(initialValue: current?.host ?? "")
        _port = State(initialValue: String(current?.port ?? 22))
    }

    private var address: SSHAddress? {
        let host = host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, let port = Int(port.trimmingCharacters(in: .whitespaces)), (1...65535).contains(port)
        else { return nil }
        return SSHAddress(host: host, port: port)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Host", text: $host, prompt: Text("203.0.113.9 or ssh.example.com"))
                        .autocorrectionDisabled()
                        #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                        #endif
                    TextField("Port", text: $port, prompt: Text("22"))
                        #if os(iOS)
                    .keyboardType(.numberPad)
                        #endif
                } footer: {
                    Text(
                        "Only this \(UnlockMethod.deviceName) uses it. Coolify keeps connecting to \(serverName) the way "
                            + "it always does."
                    )
                }
                if hasOverride {
                    Section {
                        Button("Use Coolify's Address") {
                            onSave(nil)
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("SSH Address for \(serverName)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        onSave(address)
                        dismiss()
                    }
                    .disabled(address == nil)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 260)
        #endif
    }
}

#Preview {
    AddressSheet(
        serverName: "localhost", current: SSHAddress(host: "coolify.example.com"), hasOverride: true, onSave: { _ in })
}

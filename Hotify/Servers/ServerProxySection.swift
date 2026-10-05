import CoolifyAPI
import SwiftUI

/// The proxy's type, redirect, and compose file, and the button that restarts it.
struct ServerProxySection: View {
    var model: ServerPageModel
    var canAct: Bool
    var onSave: () -> Void
    var onSaveConfiguration: () -> Void
    var onRestart: () -> Void

    @State private var confirmSettings = false
    @State private var confirmConfiguration = false

    private var heat: Heat {
        switch model.proxy?.status?.lowercased() {
        case "failed", "error": .troubled
        default: Heat(status: model.proxy?.status)
        }
    }

    private var proxyType: Binding<String> {
        Binding(get: { model.proxyTypeDraft }, set: { model.proxyTypeDraft = $0 })
    }

    private var redirectEnabled: Binding<Bool> {
        Binding(get: { model.redirectEnabledDraft }, set: { model.redirectEnabledDraft = $0 })
    }

    private var redirectURL: Binding<String> {
        Binding(get: { model.redirectURLDraft }, set: { model.redirectURLDraft = $0 })
    }

    private var configuration: Binding<String> {
        Binding(get: { model.configurationDraft }, set: { model.configurationDraft = $0 })
    }

    private var footer: String {
        "Changing the type or redirect affects every domain on this server. "
            + "Restarting the proxy drops every domain on this server until it is back."
    }

    var body: some View {
        Section {
            if model.isCoolifyHost {
                Text("This proxy is the one in front of Coolify.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    FlameGlyph(heat: heat, height: 12)
                    Text(StatusLabel.text(for: model.proxy?.status))
                        .foregroundStyle(heat.needsAttention ? AnyShapeStyle(.glow) : AnyShapeStyle(.primary))
                }
            }
            TextField("Type", text: proxyType, prompt: Text("traefik, caddy, nginx, or none"))
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            Toggle("Redirect", isOn: redirectEnabled)
            TextField("Redirect URL", text: redirectURL, prompt: Text("https://example.com"))
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
            Button {
                confirmSettings = true
            } label: {
                Label(model.write == .saveProxy ? "Saving…" : "Save Proxy", systemImage: "checkmark")
            }
            .glassButton(prominent: model.hasProxySettingChanges)
            .disabled(!canAct || !model.hasProxySettingChanges || model.isBusy)
            .help("Applies the type and redirect. Every domain on this server is affected.")
            .confirmationDialog("Change the proxy?", isPresented: $confirmSettings, titleVisibility: .visible) {
                // Destructive so Return does not confirm it on the Mac.
                Button("Save Proxy", role: .destructive, action: onSave)
            } message: {
                Text("Every domain on this server is affected.")
            }

            Text("Configuration")
                .font(.subheadline.weight(.semibold))
            if model.proxy != nil, model.returnedConfiguration == nil {
                Text("The current file was not returned. Saving replaces it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            TextEditor(text: configuration)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 140)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            Button {
                confirmConfiguration = true
            } label: {
                Label(
                    model.write == .saveProxyConfiguration ? "Saving…" : "Save Configuration",
                    systemImage: "checkmark"
                )
            }
            .glassButton(prominent: model.hasConfigurationChanges)
            .disabled(!canAct || !model.hasConfigurationChanges || model.isBusy)
            .help("Replaces the proxy compose file.")
            .confirmationDialog(
                "Replace the proxy configuration?",
                isPresented: $confirmConfiguration,
                titleVisibility: .visible
            ) {
                Button("Save Configuration", role: .destructive, action: onSaveConfiguration)
            } message: {
                Text("This replaces the compose file every domain on this server uses.")
            }

            Button(action: onRestart) {
                Label(
                    model.write == .restartProxy ? "Restarting…" : "Restart Proxy",
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            .disabled(!canAct || model.isBusy)
            .help("Every domain on this server drops until the proxy is back.")
        } header: {
            Text("Proxy")
        } footer: {
            Text(footer)
        }
    }
}

#Preview("Proxy") {
    NavigationStack {
        Form {
            ServerProxySection(
                model: .proxyOnCoolifyHost,
                canAct: true,
                onSave: {},
                onSaveConfiguration: {},
                onRestart: {}
            )
        }
    }
    .frame(width: 520, height: 760)
}

#Preview("Configuration not returned") {
    NavigationStack {
        Form {
            ServerProxySection(
                model: .proxyFileOmitted,
                canAct: true,
                onSave: {},
                onSaveConfiguration: {},
                onRestart: {}
            )
        }
    }
    .frame(width: 520, height: 640)
}

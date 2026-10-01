import CoolifyAPI
import SwiftUI

/// The form sections for a health check: what Coolify checks, then how often and how patiently.
///
/// An application can probe over HTTP or run a command. A database only has the switch and the timings, which is
/// all Coolify lets the API change there.
struct HealthCheckSection: View {
    @Binding var check: HealthCheck
    /// Whether the application's probe settings show. A database has only the timings.
    var isApplication: Bool

    private static let methods = ["GET", "HEAD", "POST", "OPTIONS"]

    private var kind: Binding<HealthCheck.Kind> {
        Binding(get: { check.kind ?? .http }, set: { check.kind = $0 })
    }

    var body: some View {
        Section {
            Toggle("Check health", isOn: $check.isEnabled)
            if isApplication, check.isEnabled {
                Picker("Check by", selection: kind) {
                    Text("HTTP request").tag(HealthCheck.Kind.http)
                    Text("Command").tag(HealthCheck.Kind.cmd)
                }
                if kind.wrappedValue == .http {
                    httpFields
                } else {
                    SettingField(title: "Command", text: text(\.command), prompt: "curl -f localhost/health")
                }
            }
        } header: {
            Text("Health Check")
        } footer: {
            Text(
                check.isEnabled
                    ? "Coolify marks the container unhealthy when the check keeps failing. Changes take effect with the next \(isApplication ? "deployment" : "restart")."
                    : "Without a check, Coolify counts the container as healthy while it runs."
            )
        }

        if check.isEnabled {
            Section("Timing") {
                NumberField(title: "Every", value: $check.interval, prompt: "5", unit: "s")
                NumberField(title: "Time out after", value: $check.timeout, prompt: "5", unit: "s")
                NumberField(title: "Unhealthy after", value: $check.retries, prompt: "10", unit: "failures")
                NumberField(title: "Grace after start", value: $check.startPeriod, prompt: "5", unit: "s")
            }
        }
    }

    @ViewBuilder
    private var httpFields: some View {
        Picker("Method", selection: choice(\.method, default: "GET")) {
            ForEach(Self.methods, id: \.self) { method in
                Text(method).tag(method)
            }
        }
        Picker("Scheme", selection: choice(\.scheme, default: "http")) {
            Text(verbatim: "http").tag("http")
            Text(verbatim: "https").tag("https")
        }
        SettingField(title: "Host", text: text(\.host), prompt: "localhost")
        NumberField(title: "Port", value: $check.port, prompt: "Exposed port")
        SettingField(title: "Path", text: text(\.path), prompt: "/")
        NumberField(title: "Expected status", value: $check.returnCode, prompt: "200")
        SettingField(title: "Expected text", text: text(\.responseText), prompt: "Any")
    }

    /// An optional text field as a plain string. Clearing it stores `nil`, so a field left empty matches the loaded one.
    private func text(_ field: WritableKeyPath<HealthCheck, String?>) -> Binding<String> {
        Binding(
            get: { check[keyPath: field] ?? "" },
            set: { check[keyPath: field] = $0.isEmpty ? nil : $0 }
        )
    }

    private func choice(_ field: WritableKeyPath<HealthCheck, String?>, default fallback: String) -> Binding<String> {
        Binding(
            get: { check[keyPath: field] ?? fallback },
            set: { check[keyPath: field] = $0 }
        )
    }
}

#Preview("Application") {
    @Previewable @State var check = HealthCheck(
        isEnabled: true, kind: .http, method: "GET", scheme: "http", host: "localhost", path: "/health",
        returnCode: 200, interval: 30, timeout: 5, retries: 3, startPeriod: 10)
    Form {
        HealthCheckSection(check: $check, isApplication: true)
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 640)
}

#Preview("Database") {
    @Previewable @State var check = HealthCheck(isEnabled: true, interval: 15, timeout: 5, retries: 5, startPeriod: 5)
    Form {
        HealthCheckSection(check: $check, isApplication: false)
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 400)
}

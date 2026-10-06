import CoolifyAPI
import SwiftUI

/// Domains on the server, grouped by the address they use.
struct ServerDomainList: View {
    var groups: [ServerDomainGroup]

    var body: some View {
        Section("Domains") {
            if groups.isEmpty {
                Text("No domains on this server.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "network")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(group.ip.isEmpty ? "No address" : group.ip)
                                .font(.body.monospaced().weight(.semibold))
                                .textSelection(.enabled)
                            Spacer(minLength: 8)
                            Text(group.domains.count == 1 ? "1 domain" : "\(group.domains.count) domains")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        if group.domains.isEmpty {
                            Text("No domains")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(group.domains, id: \.self) { domain in
                                domainLine(domain)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    /// Coolify lists a domain without its scheme. It opens over HTTPS, the way the proxy serves it.
    @ViewBuilder
    private func domainLine(_ domain: String) -> some View {
        let address = domain.contains("://") ? domain : "https://\(domain)"
        if let url = URL(string: address), url.host() != nil {
            Link(destination: url) {
                HStack(spacing: 4) {
                    Text(domain)
                    Image(systemName: "arrow.up.right")
                        .imageScale(.small)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.tint)
            .lineLimit(1)
            .padding(.leading, 26)
            .help("Open \(domain)")
        } else {
            Text(domain)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.leading, 26)
        }
    }
}

#Preview {
    NavigationStack {
        Form {
            ServerDomainList(
                groups: [
                    ServerDomainGroup(ip: "10.0.0.8", domains: ["app.example.com", "api.example.com"]),
                    ServerDomainGroup(ip: "10.0.0.9", domains: []),
                ]
            )
        }
    }
    .frame(width: 480, height: 280)
}

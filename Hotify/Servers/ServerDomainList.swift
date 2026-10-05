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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.ip.isEmpty ? "No address" : group.ip)
                            .font(.body.weight(.semibold))
                            .textSelection(.enabled)
                        if group.domains.isEmpty {
                            Text("No domains")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(group.domains, id: \.self) { domain in
                                Text(domain)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
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

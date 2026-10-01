import CoolifyAPI
import SwiftUI

/// Explains a stopped provisioning step and offers the way out: new token, other domains, or trying again.
struct ProblemNotice: View {
    var problem: ProvisioningProblem
    /// The instance's web address, for a link to its token settings.
    var instanceRoot: URL?
    /// Repeats the request with `force_domain_override`. Only offered for conflicts.
    var onOverride: (() -> Void)?

    var body: some View {
        switch problem {
        case .permission(let message):
            card(
                title: "This token can't create resources",
                detail:
                    "Coolify said: “\(message.trimmingCharacters(in: CharacterSet(charactersIn: ".")))”. Make a token with the root permission under Keys & Tokens, then paste it into Edit Instance in Hotify.",
                link: tokensURL.map { ("Open Keys & Tokens", $0) }
            )
        case .signedOut:
            card(
                title: "Coolify no longer accepts this token",
                detail: "It may have been revoked or have expired. Make a new one and paste it into Edit Instance.",
                link: tokensURL.map { ("Open Keys & Tokens", $0) }
            )
        case .unknownTemplate(let slug):
            card(
                title: "This instance doesn't know \(slug) yet",
                detail:
                    "Coolify keeps its own copy of the catalog. Reload the service list on Coolify's New Resource page, or update Coolify, then try again.",
                link: instanceRoot.map { ("Open Coolify", $0) }
            )
        case .conflicts(let conflicts):
            conflictCard(conflicts)
        case .message(let message):
            NoticeBanner(message: message)
        }
    }

    private var tokensURL: URL? {
        instanceRoot?.appending(path: "security/api-tokens")
    }

    private func card(title: String, detail: String, link: (String, URL)?) -> some View {
        HStack(alignment: .top, spacing: 14) {
            FlameGlyph(heat: .troubled, height: 26)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let (label, url) = link {
                    Link(destination: url) {
                        Label(label, systemImage: "arrow.up.right")
                    }
                    .font(.callout.weight(.semibold))
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.glow.opacity(0.12), in: .rect(cornerRadius: 14))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func conflictCard(_ conflicts: [DomainConflict]) -> some View {
        HStack(alignment: .top, spacing: 14) {
            FlameGlyph(heat: .troubled, height: 26)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 8) {
                Text(conflicts.count == 1 ? "This address is taken" : "These addresses are taken")
                    .font(.headline)
                ForEach(conflicts, id: \.self) { conflict in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: conflict.domain)
                            .font(.callout.monospaced().weight(.medium))
                        if let owner = conflict.resourceName {
                            Text("Used by \(owner)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text(
                    "Two resources on one address split its traffic unpredictably. Pick another address, or use it anyway."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                if let onOverride {
                    Button("Use Anyway", action: onOverride)
                        .glassButton()
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.glow.opacity(0.12), in: .rect(cornerRadius: 14))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            ProblemNotice(
                problem: .permission("Missing required permissions: write"),
                instanceRoot: URL(string: "https://coolify.example.com"))
            ProblemNotice(
                problem: .conflicts([DomainConflict(domain: "blog.example.com", resourceName: "marketing-site")]),
                onOverride: {})
            ProblemNotice(problem: .message("Server has no destinations."))
        }
        .padding(24)
    }
    .frame(width: 560, height: 560)
}

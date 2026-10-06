import CoolifyAPI
import SwiftUI

/// The server at a glance, under its name: how the proxy is, how the last Docker cleanup went, and how many domains it
/// serves. A rim of fire circles the panel while a validation, cleanup, or proxy restart is in flight.
struct ServerVitals: View {
    var model: ServerPageModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                proxy
                divider(vertical: true)
                cleanup
                divider(vertical: true)
                domains
            }
            VStack(spacing: 0) {
                proxy
                divider(vertical: false)
                cleanup
                divider(vertical: false)
                domains
            }
        }
        .well()
        .heatEdge(isActive: model.isBusy)
        .animation(.snappy, value: model.proxy)
        .animation(.snappy, value: model.executions.first?.id)
        .animation(.snappy, value: model.domainCount)
    }

    private func divider(vertical: Bool) -> some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
            .padding(vertical ? .vertical : .horizontal, 12)
    }

    private var proxyHeat: Heat {
        if model.write == .restartProxy { return .warming }
        return model.proxy?.heat ?? .unknown
    }

    private var proxy: some View {
        VitalTile(
            title: "Proxy",
            value: model.proxy?.typeLabel ?? "Unknown",
            detail: model.write == .restartProxy ? "Restarting…" : StatusLabel.text(for: model.proxy?.status),
            heat: proxyHeat
        )
    }

    private var cleanupHeat: Heat {
        if model.write == .runCleanup { return .warming }
        return model.executions.first?.heat ?? .unknown
    }

    private var cleanupDetail: String {
        if model.write == .runCleanup { return "Cleaning…" }
        guard let last = model.executions.first else { return "No runs yet" }
        guard let date = last.finishedAtDate ?? last.createdAtDate else { return last.status.capitalized }
        return date.formatted(.relative(presentation: .named))
    }

    private var cleanup: some View {
        VitalTile(
            title: "Docker cleanup",
            value: model.settings?.frequencyLabel ?? "Not scheduled",
            detail: cleanupDetail,
            heat: cleanupHeat
        )
    }

    private var domains: some View {
        VitalTile(
            title: "Domains",
            value: model.domainCount == 1 ? "1 domain" : "\(model.domainCount) domains",
            detail: model.addressCount == 1 ? "On 1 address" : "On \(model.addressCount) addresses",
            symbol: "globe"
        )
    }
}

/// One fact on the vitals panel. A heat shows as a flame; a plain fact gets a symbol.
private struct VitalTile: View {
    var title: String
    var value: String
    var detail: String
    var heat: Heat?
    var symbol: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let heat {
                    FlameGlyph(heat: heat, height: 20)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 20, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(value)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .contentTransition(.interpolate)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(heat?.needsAttention == true ? AnyShapeStyle(.glow) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .contentTransition(.interpolate)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension ServerProxy {
    /// `Traefik` for `TRAEFIK`, and `No proxy` when Coolify runs none.
    fileprivate var typeLabel: String {
        let type = proxyType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch type.lowercased() {
        case "": return "Unknown"
        case "none": return "No proxy"
        default: return type.prefix(1).uppercased() + type.dropFirst().lowercased()
        }
    }
}

extension DockerCleanupSettings {
    /// The schedule in words where Coolify uses a word, and the cron expression otherwise.
    fileprivate var frequencyLabel: String? {
        guard let frequency = dockerCleanupFrequency?.trimmingCharacters(in: .whitespacesAndNewlines),
            !frequency.isEmpty
        else { return nil }
        return frequency.contains(" ") ? frequency : frequency.capitalized
    }
}

extension ServerPageModel {
    fileprivate var domainCount: Int { domains.reduce(0) { $0 + $1.domains.count } }
    fileprivate var addressCount: Int { domains.filter { !$0.domains.isEmpty }.count }
}

#Preview {
    VStack(spacing: 24) {
        ServerVitals(model: .sample)
        ServerVitals(model: .sample)
            .frame(width: 360)
    }
    .padding(24)
    .frame(width: 640)
}

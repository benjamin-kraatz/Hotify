import SwiftUI

// The top of the dashboard, as separate list rows. A macOS List keeps the height it first measured for a row,
// so each piece holds a fixed shape and new facts arrive as new rows rather than a taller one.

/// The instance name on macOS, then the team and Coolify version.
struct DashboardTitle: View {
    var instanceName: String
    var teamName: String
    var version: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            #if os(macOS)
            Text(instanceName)
                .font(.display(.title))
                .lineLimit(1)
            #endif
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // A space keeps the line's height while the team loads.
                Text(teamName.isEmpty ? " " : teamName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("Coolify \(version)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary.opacity(0.7), in: .capsule)
                    .opacity(version.isEmpty ? 0 : 1)
            }
        }
        .padding(.top, 6)
        .animation(.snappy, value: teamName)
        .animation(.snappy, value: version)
    }
}

/// A heat strip of every resource and how many of them run.
struct HeatSummary: View {
    var heats: [Heat]

    private var runningCount: Int { heats.filter { $0 == .lit }.count }

    private var attentionCount: Int { heats.filter(\.needsAttention).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeatStrip(heats: heats)
            HStack(spacing: 12) {
                Text("\(runningCount) of \(heats.count) running")
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                Label(
                    attentionCount == 1 ? "1 needs a look" : "\(attentionCount) need a look",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.glow)
                .contentTransition(.numericText())
                .opacity(attentionCount > 0 ? 1 : 0)
            }
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .animation(.snappy, value: runningCount)
        .animation(.snappy, value: attentionCount)
    }
}

/// A server name with whether Coolify can reach it.
struct ServerStatusLine: View {
    var server: ServerLine

    private var heat: Heat {
        switch server.isReachable {
        case true: .lit
        case false: .troubled
        default: .unknown
        }
    }

    private var label: String {
        switch server.isReachable {
        case true: "Reachable"
        case false: "Unreachable"
        default: "Unknown"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "server.rack")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(server.name)
                .lineLimit(1)
            Spacer(minLength: 8)
            FlameGlyph(heat: heat, height: 12)
            Text(label)
                .foregroundStyle(heat == .troubled ? AnyShapeStyle(.glow) : AnyShapeStyle(.secondary))
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    List {
        DashboardTitle(instanceName: "Home lab", teamName: "Root Team", version: "4.3.23")
        HeatSummary(heats: [.lit, .lit, .cold, .troubled, .warming])
        ServerStatusLine(server: ServerLine(id: "1", name: "localhost", isReachable: true))
    }
    .frame(width: 380, height: 300)
}

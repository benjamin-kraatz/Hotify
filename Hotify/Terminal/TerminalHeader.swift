import SwiftUI

/// The chrome above the canvas: what the shell runs in, where it signed in, how the connection is doing, and the
/// actions the screen offers.
///
/// The flame reads the connection: lit while a shell runs, amber on the way there or after a drop, cold once the
/// shell exited. The second line follows the program's title when it sets one, the way a window title would.
struct TerminalHeader: View {
    var heading: String
    var serverName: String?
    /// Who the shell signed in as, and where.
    var destination: String?
    var heat: Heat
    var linkLabel: String
    var latency: Duration?
    /// The title the program set, if any.
    var title: String?
    /// The shell's working directory, when it reports it.
    var directory: String?
    var showsActions = false
    var offersAddress = false
    var onRun: (TerminalSnippet) -> Void = { _ in }
    var onFind: () -> Void = {}
    var onZoom: (TerminalZoom) -> Void = { _ in }
    var onClear: () -> Void = {}
    var onAddress: () -> Void = {}

    private var subtitle: String? {
        if let title, !title.isEmpty {
            return title
        }
        return [serverName, destination, directory].compactMap { $0 }.joined(separator: " · ")
            .nilIfEmpty
    }

    private var latencyText: String? {
        guard let latency else { return nil }
        let milliseconds = Int((latency / .milliseconds(1)).rounded())
        return milliseconds < 1 ? "<1 ms" : "\(milliseconds) ms"
    }

    var body: some View {
        HStack(spacing: 12) {
            FlameGlyph(heat: heat, height: 30)
                .frame(width: 22)
                .accessibilityLabel(linkLabel)
            VStack(alignment: .leading, spacing: 2) {
                Text(heading)
                    .font(.headline)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .contentTransition(.opacity)
                }
            }
            Spacer(minLength: 8)
            status
            if showsActions {
                SnippetMenu(onRun: onRun)
                    .menuStyle(.button)
                    .fixedSize()
                Button("Find", systemImage: "magnifyingglass", action: onFind)
                    .help("Find in the scrollback")
            }
            Menu {
                if showsActions {
                    Button("Bigger Text", systemImage: "plus.magnifyingglass") { onZoom(.bigger) }
                    Button("Smaller Text", systemImage: "minus.magnifyingglass") { onZoom(.smaller) }
                    Button("Actual Size", systemImage: "1.magnifyingglass") { onZoom(.reset) }
                    Divider()
                    Button("Clear Scrollback", systemImage: "eraser", action: onClear)
                }
                if offersAddress {
                    if showsActions {
                        Divider()
                    }
                    Button("SSH Address…", systemImage: "network", action: onAddress)
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .menuStyle(.button)
            .fixedSize()
            .disabled(!showsActions && !offersAddress)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .animation(.snappy, value: heat)
        .animation(.snappy, value: latencyText)
    }

    @ViewBuilder
    private var status: some View {
        #if os(macOS)
        HStack(spacing: 6) {
            Text(linkLabel)
                .foregroundStyle(heat.needsAttention ? AnyShapeStyle(.glow) : AnyShapeStyle(.secondary))
                .contentTransition(.opacity)
            if let latencyText {
                Text(latencyText)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
            }
        }
        .font(.caption)
        .lineLimit(1)
        .fixedSize()
        #else
        if let latencyText {
            Text(latencyText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .contentTransition(.numericText())
                .fixedSize()
        }
        #endif
    }
}

/// A step of the terminal's text size.
enum TerminalZoom {
    case bigger
    case smaller
    case reset
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}

#Preview("Connected") {
    VStack(spacing: 16) {
        TerminalHeader(
            heading: "backend",
            serverName: "edge-1",
            destination: "root@203.0.113.9",
            heat: .lit,
            linkLabel: "Connected",
            latency: .milliseconds(42),
            showsActions: true,
            offersAddress: true
        )
        TerminalHeader(
            heading: "backend",
            serverName: "edge-1",
            destination: "root@203.0.113.9",
            heat: .lit,
            linkLabel: "Connected",
            latency: .milliseconds(42),
            title: "vim config/app.yml",
            showsActions: true,
            offersAddress: true
        )
        TerminalHeader(
            heading: "postgres",
            serverName: "edge-1",
            destination: "root@203.0.113.9",
            heat: .troubled,
            linkLabel: "Connection dropped",
            offersAddress: true
        )
        TerminalHeader(
            heading: "postgres",
            serverName: "edge-1",
            destination: "root@203.0.113.9",
            heat: .warming,
            linkLabel: "Connecting"
        )
    }
    .padding(20)
    .frame(width: 560)
}

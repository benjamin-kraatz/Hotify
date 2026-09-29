import SwiftUI

/// Container output, newest at the bottom. Follows new lines until you scroll up to read.
struct LogView: View {
    var lines: [LogLine]
    var rawLogs: String
    var isLoading: Bool
    @Binding var lineCount: Int
    /// Service containers to choose from. Empty for applications and databases, which have one log.
    var showsLineCount = true
    var sources: [ContainerSummary] = []
    var sourceID: Binding<Int?> = .constant(nil)
    /// Shown in place of the log when there is nothing Coolify will serve, such as a stopped container.
    var pausedMessage: String?

    @State private var filter = ""
    @State private var isAtBottom = true
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var copies = 0

    private static let lineCounts = [100, 500, 1_000]

    private var shown: [LogLine] {
        let trimmed = filter.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return lines }
        return lines.filter { $0.text.localizedStandardContains(trimmed) }
    }

    var body: some View {
        VStack(spacing: 10) {
            controls
            logWell
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if sources.count > 1 {
                Picker("Container", selection: sourceID) {
                    ForEach(sources) { source in
                        Label {
                            Text(source.name)
                        } icon: {
                            Image(systemName: source.heat == .cold ? "flame" : "flame.fill")
                        }
                        .tag(Optional(source.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .help("Which container's output to show")
            }

            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(.secondary)
                TextField("Filter lines", text: $filter)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    #if os(iOS)
                .textInputAutocapitalization(.never)
                    #endif
                if !filter.isEmpty {
                    Button("Clear filter", systemImage: "xmark.circle.fill") {
                        filter = ""
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.6), in: .capsule)
            .animation(.snappy, value: filter.isEmpty)

            if showsLineCount {
                Menu {
                    Picker("Lines", selection: $lineCount) {
                        ForEach(Self.lineCounts, id: \.self) { count in
                            Text("Last \(count) lines").tag(count)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("\(lineCount) lines", systemImage: "text.alignleft")
                        .monospacedDigit()
                }
                .menuStyle(.button)
                .fixedSize()
                .help("How many recent lines to load")
            }

            Button {
                copyLogs()
            } label: {
                Label("Copy logs", systemImage: copies > 0 ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .labelStyle(.iconOnly)
            .disabled(rawLogs.isEmpty)
            .help("Copy all loaded lines")
            .task(id: copies) {
                guard copies > 0 else { return }
                try? await Task.sleep(for: .seconds(1.5))
                copies = 0
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.regular)
    }

    private var logWell: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
                ForEach(shown) { line in
                    LogLineRow(line: line)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 32
        } action: { _, atBottom in
            isAtBottom = atBottom
        }
        .onChange(of: lines) { _, _ in
            guard isAtBottom else { return }
            withAnimation(.smooth) {
                position.scrollTo(edge: .bottom)
            }
        }
        .background(Color.primary.opacity(0.045), in: .rect(cornerRadius: 14))
        .overlay {
            if let pausedMessage {
                ContentUnavailableView {
                    Label {
                        Text("No output while stopped")
                    } icon: {
                        FlameGlyph(heat: .cold, height: 40)
                    }
                } description: {
                    Text(pausedMessage)
                }
            } else if lines.isEmpty {
                if isLoading {
                    ProgressView()
                } else {
                    ContentUnavailableView(
                        "No output yet",
                        systemImage: "text.alignleft",
                        description: Text("Coolify returned no log lines for this resource.")
                    )
                }
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: filter)
            }
        }
        .overlay(alignment: .bottom) {
            if !isAtBottom, !shown.isEmpty {
                Button {
                    withAnimation(.smooth) {
                        position.scrollTo(edge: .bottom)
                    }
                } label: {
                    Label("Latest", systemImage: "arrow.down")
                }
                .glassButton()
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: isAtBottom)
    }

    private func copyLogs() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rawLogs, forType: .string)
        #else
        UIPasteboard.general.string = rawLogs
        #endif
        copies += 1
    }
}

/// One log line: a dim timestamp, then the message. Lines that mention errors or warnings glow amber.
private struct LogLineRow: View {
    var line: LogLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let timestamp = line.timestamp {
                Text(timestamp, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute().second())
                    .foregroundStyle(.tertiary)
                    .help(timestamp.formatted(date: .abbreviated, time: .standard))
            }
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(line.isAlarming ? AnyShapeStyle(.glow) : AnyShapeStyle(.primary))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.caption, design: .monospaced))
    }
}

#Preview {
    @Previewable @State var lineCount = 100
    let logs = """
        2026-09-29T08:00:00.123456789Z Starting server
        2026-09-29T08:00:00.523456789Z listening on :3000
        2026-09-29T08:00:02.000000000Z GET /health 200 2ms
        2026-09-29T08:00:05.000000000Z warn: slow query took 812ms
        2026-09-29T08:00:07.000000000Z error: connection reset by peer
        2026-09-29T08:00:09.000000000Z GET /health 200 1ms
        """
    LogView(lines: LogLine.parse(logs), rawLogs: logs, isLoading: false, lineCount: $lineCount)
        .frame(height: 320)
}

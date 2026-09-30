#if os(macOS)
import AppKit
import SwiftUI

/// The menu bar window: how the watched resources are doing, each one a click away from the main window.
struct MenuBarView: View {
    @SwiftUI.Environment(MenuBarModel.self) private var model
    @SwiftUI.Environment(\.openWindow) private var openWindow

    /// Watched resources by instance, in the order they were added.
    private var groups: [(instance: String, entries: [WatchedResource])] {
        var order: [UUID] = []
        var byInstance: [UUID: [WatchedResource]] = [:]
        for entry in model.watched {
            if byInstance[entry.instanceID] == nil { order.append(entry.instanceID) }
            byInstance[entry.instanceID, default: []].append(entry)
        }
        return order.map { id in
            let entries = byInstance[id] ?? []
            return (entries.first?.instanceName ?? "", entries)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Staleness is a matter of time, so the window re-reads it between refreshes.
            TimelineView(.periodic(from: .now, by: 10)) { _ in
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if model.watched.isEmpty {
                        empty
                    } else {
                        list
                    }
                }
            }
            Divider()
            footer
        }
        .frame(width: 340)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                FlameGlyph(heat: model.heats.contains(.lit) ? .lit : .cold, height: 20)
                Text("Hotify")
                    .font(.display(.title3))
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(model.refreshing)
                .help("Check every watched resource now")
            }
            if !model.watched.isEmpty {
                HeatSummary(heats: model.heats)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(groups, id: \.instance) { group in
                    // One instance needs no heading. Its name is on every resource's screen anyway.
                    if groups.count > 1 {
                        Text(group.instance)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                    }
                    ForEach(group.entries) { entry in
                        MenuBarRow(entry: entry, state: model.state(for: entry)) {
                            model.open(entry)
                            openMainWindow()
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .frame(maxHeight: 360)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            FlameGlyph(heat: .cold, height: 36)
                .padding(.bottom, 2)
            Text("Nothing watched yet")
                .font(.headline)
            Text("Open a resource in Hotify and use the menu bar button in its toolbar, or pick some in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 22)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button("Open Hotify", action: openMainWindow)
            Spacer()
            if let checked = model.lastChecked {
                Text("Checked \(checked.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SettingsLink {
                Label("Settings", systemImage: "gear")
            }
            .labelStyle(.iconOnly)
            .help("Settings")
            Button("Quit Hotify", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
            .labelStyle(.iconOnly)
            .help("Quit Hotify and stop watching")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

/// One watched resource, laid out like its row in the dashboard.
private struct MenuBarRow: View {
    var entry: WatchedResource
    var state: MenuBarResourceState
    var onOpen: () -> Void

    @State private var isHovered = false

    private var kind: ResourceKind? { entry.route?.kind }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                FlameGlyph(heat: state.heat, height: 17)
                    .frame(width: 16)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(state.resource?.name ?? entry.name)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(state.statusText)
                            .font(.subheadline)
                            .foregroundStyle(
                                state.heat.needsAttention || state.isStale
                                    ? AnyShapeStyle(.glow) : AnyShapeStyle(.secondary)
                            )
                            .contentTransition(.interpolate)
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        if let kind {
                            Image(systemName: kind.systemImage)
                                .imageScale(.small)
                                .accessibilityLabel(kind.title)
                        }
                        Text(state.resource?.subtitle ?? kind?.title ?? "")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(isHovered ? 0.07 : 0), in: .rect(cornerRadius: 9))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.15), value: isHovered)
        .animation(.snappy, value: state.statusText)
        .help("Open \(entry.name) in Hotify")
        .accessibilityElement(children: .combine)
        .accessibilityValue(state.statusText)
    }
}

#Preview { MenuBarView().environment(MenuBarModel(preview: true)) }
#endif

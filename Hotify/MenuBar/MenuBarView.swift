#if os(macOS)
import AppKit
import SwiftUI

/// A compact status list with navigation to the main window.
struct MenuBarView: View {
    @SwiftUI.Environment(MenuBarModel.self) private var model
    @SwiftUI.Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Hotify").font(.display(.title2))
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                    .labelStyle(.iconOnly).disabled(model.refreshing)
            }
            if model.watched.isEmpty {
                Text("Choose resources in Settings to watch them here.").foregroundStyle(.secondary)
            }
            ScrollView {
                TimelineView(.periodic(from: .now, by: 10)) { _ in
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.watched) { entry in
                            let state = model.snapshots[entry.id] ?? MenuBarResourceState()
                            Button {
                                model.open(entry)
                                openMainWindow()
                            } label: {
                                HStack(spacing: 10) {
                                    FlameGlyph(heat: state.heat, height: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(state.resource?.name ?? entry.name).font(.headline)
                                        Text(entry.instanceName).font(.caption).foregroundStyle(.secondary)
                                        Text(
                                            state.message
                                                ?? (state.isStale
                                                    ? "Waiting for a fresh status"
                                                    : (state.resource?.isDeploying == true
                                                        ? "Deploying" : state.resource?.status ?? "Unknown"))
                                        )
                                        .font(.caption).foregroundStyle(state.isStale ? .glow : .secondary)
                                        if let updated = state.updatedAt {
                                            Text("Checked \(updated.formatted(date: .omitted, time: .standard))").font(
                                                .caption2
                                            ).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxHeight: 350)
            Divider()
            HStack {
                Button("Open Hotify", action: openMainWindow)
                SettingsLink { Image(systemName: "gear") }.help("Settings")
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

#Preview { MenuBarView().environment(MenuBarModel(preview: true)) }
#endif

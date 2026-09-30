#if os(macOS)
import CoolifyAPI
import SwiftUI

/// Adds the open resource to the menu bar, or takes it out again. For the detail toolbar.
struct MenuBarWatchButton: View {
    @SwiftUI.Environment(InstanceStore.self) private var store: InstanceStore?
    var model: MenuBarModel
    var resource: ResourceSummary

    private var entry: WatchedResource? {
        store?.selected.map { WatchedResource(instanceID: $0.id, instanceName: $0.name, resource: resource) }
    }

    private var isWatching: Bool {
        entry.map(model.isWatching) ?? false
    }

    var body: some View {
        Button(
            isWatching ? "Remove from Menu Bar" : "Watch in Menu Bar",
            systemImage: isWatching ? "menubar.arrow.up.rectangle" : "menubar.rectangle"
        ) {
            guard let entry else { return }
            if isWatching {
                model.remove(entry)
            } else {
                model.add(entry)
            }
        }
        .symbolVariant(isWatching ? .fill : .none)
        .contentTransition(.symbolEffect(.replace))
        .disabled(entry == nil)
        .help(
            isWatching
                ? "Stop showing \(resource.name) in the menu bar"
                : "Show \(resource.name) in the menu bar, where Hotify keeps checking it"
        )
    }
}

#Preview {
    MenuBarWatchButton(
        model: MenuBarModel(preview: true),
        resource: ResourceSummary(route: .application("web"), name: "marketing-site", status: "running:healthy")
    )
    .padding()
    .environment(InstanceStore(instances: []))
}
#endif

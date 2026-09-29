#if os(macOS)
import SwiftUI

/// Opts into background monitoring and chooses the resources shown in the menu bar.
struct MenuBarSettings: View {
    @SwiftUI.Environment(MenuBarModel.self) private var model
    @State private var selection: ResourceEndpoint?

    var body: some View {
        @Bindable var model = model
        Section {
            Toggle("Show Hotify in the menu bar", isOn: $model.enabled)
            Text(
                "When enabled, Hotify keeps running after its last window closes and refreshes watched resources every 15 seconds."
            )
            .font(.caption).foregroundStyle(.secondary)
            if model.enabled {
                ForEach(model.watched) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.name)
                            Text(entry.instanceName).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove", systemImage: "minus.circle") { model.remove(entry) }.labelStyle(.iconOnly)
                    }
                }
            }
        } header: {
            Text("Menu bar")
        }
        if model.enabled {
            ResourcePicker(title: "Watch a resource", endpoint: $selection)
            Button("Add to menu bar") {
                guard let selection else { return }
                model.add(
                    WatchedResource(
                        instanceID: selection.instanceID, instanceName: selection.instanceName,
                        resource: selection.resource))
                self.selection = nil
            }.disabled(selection == nil)
        }
    }
}

#Preview {
    Form { MenuBarSettings() }
        .environment(MenuBarModel(preview: true))
        .environment(InstanceStore(instances: []))
}
#endif

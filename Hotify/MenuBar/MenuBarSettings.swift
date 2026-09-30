#if os(macOS)
import SwiftUI

/// Opts into background monitoring and chooses the resources shown in the menu bar.
struct MenuBarSettings: View {
    @SwiftUI.Environment(MenuBarModel.self) private var model
    @State private var selection: ResourceEndpoint?

    private var candidate: WatchedResource? {
        selection.map {
            WatchedResource(instanceID: $0.instanceID, instanceName: $0.instanceName, resource: $0.resource)
        }
    }

    var body: some View {
        @Bindable var model = model
        Section {
            Toggle(isOn: $model.enabled) {
                Label {
                    Text("Show Hotify in the menu bar")
                    Text(
                        "Hotify keeps running after its last window closes and checks the watched resources every 15 seconds."
                    )
                } icon: {
                    Image(systemName: "menubar.rectangle")
                        .foregroundStyle(.ember)
                }
            }
        } header: {
            Text("Menu Bar")
        }

        if model.enabled {
            Section {
                ForEach(model.watched) { entry in
                    HStack(spacing: 10) {
                        FlameGlyph(heat: model.state(for: entry).heat, height: 18)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(entry.instanceName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Button("Stop Watching \(entry.name)", systemImage: "minus.circle.fill") {
                            model.remove(entry)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Take \(entry.name) out of the menu bar")
                    }
                }
                if model.watched.isEmpty {
                    Text(
                        "Nothing watched yet. Add a resource below, or use the menu bar button in a resource's toolbar."
                    )
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Watched Resources")
            }

            Section {
                ResourcePicker(endpoint: $selection)
                HStack {
                    Spacer()
                    Button("Watch in Menu Bar") {
                        guard let candidate else { return }
                        model.add(candidate)
                        selection = nil
                    }
                    .disabled(candidate.map(model.isWatching) ?? true)
                }
            } header: {
                Text("Watch Another Resource")
            }
        }
    }
}

#Preview {
    Form { MenuBarSettings() }
        .formStyle(.grouped)
        .environment(MenuBarModel(preview: true))
        .environment(InstanceStore(instances: []))
        .frame(width: 500)
}
#endif

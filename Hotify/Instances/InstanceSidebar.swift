import CoolifyAPI
import SwiftUI

/// The saved instances. Right-click, or swipe on iPhone, to edit or remove one.
struct InstanceSidebar: View {
    @SwiftUI.Environment(InstanceStore.self) private var store
    @Binding var isAdding: Bool
    @Binding var editing: CoolifyInstance?
    /// Whether the window hides the sidebar. Its toolbar actions go with it.
    var isCollapsed = false
    /// The heat of an instance: lit when its dashboard loads, amber when it fails, dashed when Hotify is not watching.
    var heat: (CoolifyInstance) -> Heat

    @State private var removing: CoolifyInstance?
    @State private var isShowingSettings = false

    var body: some View {
        @Bindable var store = store

        List(selection: $store.selectedID) {
            ForEach(store.instances) { instance in
                InstanceRow(instance: instance, heat: heat(instance))
                    .tag(instance.id)
                    .contextMenu {
                        Button("Edit…", systemImage: "pencil") {
                            editing = instance
                        }
                        Button("Remove…", systemImage: "trash", role: .destructive) {
                            removing = instance
                        }
                    }
                    #if os(iOS)
                .swipeActions(edge: .leading) {
                    Button("Edit", systemImage: "pencil") {
                        editing = instance
                    }
                    .tint(.glow)
                }
                .swipeActions {
                    Button("Remove", systemImage: "trash") {
                        removing = instance
                    }
                    .tint(.red)
                }
                    #endif
            }
        }
        #if os(macOS)
        .listStyle(.sidebar)
        #endif
        .safeAreaInset(edge: .bottom) {
            Wordmark()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .navigationTitle("Instances")
        .toolbar {
            // The Mac keeps a hidden sidebar's items before the sidebar button, where only one fits, and moves
            // the rest to an overflow menu at the far end of the toolbar. File > New Instance still adds one.
            if !isCollapsed {
                ToolbarItemGroup {
                    if let selected = store.selected {
                        Button("Edit Instance", systemImage: "pencil") {
                            editing = selected
                        }
                        .help("Edit \(selected.name)")
                    }
                    Button("Add Instance", systemImage: "plus") {
                        isAdding = true
                    }
                    .help("Add a Coolify instance (⌘N)")
                }
            }
            // The Mac has a Settings window in the app menu instead.
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gear") {
                    isShowingSettings = true
                }
            }
            #endif
        }
        #if os(iOS)
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
                SettingsView()
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            isShowingSettings = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        #endif
        .confirmationDialog(
            removing.map { "Remove \($0.name)?" } ?? "",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible,
            presenting: removing
        ) { instance in
            Button("Remove", role: .destructive) {
                withAnimation(.snappy) {
                    store.remove(instance)
                }
            }
        } message: { _ in
            Text(
                "Hotify removes this instance and its API token from all your synced devices. Nothing changes on the server."
            )
        }
    }
}

private struct InstanceRow: View {
    var instance: CoolifyInstance
    var heat: Heat

    var body: some View {
        HStack(spacing: 10) {
            FlameGlyph(heat: heat, height: 18)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(instance.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(instance.displayHost)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 3)
    }
}

/// The small flame and name at the foot of the sidebar.
private struct Wordmark: View {
    var body: some View {
        HStack(spacing: 7) {
            FlameGlyph(heat: .lit, height: 15)
            Text("Hotify")
                .font(.display(.subheadline))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hotify")
    }
}

#Preview {
    let namesAndURLs = [
        ("Production", "https://coolify.example.com"),
        ("Staging", "https://staging.example.com"),
        ("Home lab", "http://10.0.0.4:8000"),
    ]
    let instances = namesAndURLs.compactMap { name, address in
        URL(string: address).map { CoolifyInstance(name: name, baseURL: $0) }
    }

    NavigationStack {
        InstanceSidebar(isAdding: .constant(false), editing: .constant(nil)) { instance in
            instance.name == "Production" ? .lit : .unknown
        }
    }
    .environment(InstanceStore(instances: instances))
    .environment(VariableLock(isRequired: true))
}

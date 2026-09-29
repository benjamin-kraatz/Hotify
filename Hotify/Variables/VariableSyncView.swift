import CoolifyAPI
import SwiftUI

/// Manual cross-instance comparison, reviewed copying, and optional destination matching.
struct VariableSyncView: View {
    @SwiftUI.Environment(InstanceStore.self) private var store
    @SwiftUI.Environment(VariableLock.self) private var lock
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @State var source: ResourceEndpoint?
    @State private var destination: ResourceEndpoint?
    @State private var sourcePreview = false
    @State private var destinationPreview = false
    @State private var model = VariableSyncModel()
    @State private var confirmActivation = false
    var onChanged: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                if !lock.isOpen {
                    Section {
                        Text("Unlock values to compare or sync variables.")
                        Button("Unlock") { Task { await lock.unlock() } }
                        if let failure = lock.failure { NoticeBanner(message: failure) }
                    }
                } else {
                    if !model.reviewing {
                        ResourcePicker(title: "Source", endpoint: $source)
                        if source?.resource.kind == .application {
                            Toggle("Source preview variables", isOn: $sourcePreview)
                        }
                        ResourcePicker(title: "Destination", endpoint: $destination)
                        if destination?.resource.kind == .application {
                            Toggle("Destination preview variables", isOn: $destinationPreview)
                        }
                        Section {
                            Button("Swap direction", systemImage: "arrow.up.arrow.down") {
                                swap(&source, &destination)
                                swap(&sourcePreview, &destinationPreview)
                            }
                            Button("Compare variables") { Task { await compare() } }
                                .disabled(source == nil || destination == nil)
                        }
                        .disabled(model.busy)
                    }
                    if let plan = model.plan { comparison(plan) }
                    if let message = model.message { Section { Text(message) } }
                    if let endpoint = model.changedDestination {
                        Section("Apply saved changes") {
                            Text("\(endpoint.label) · \(model.changedPreview ? "Preview" : "Production")")
                            if model.changedPreview {
                                Text("Redeploy the affected preview deployments in Coolify to use these variables.")
                            } else {
                                Button(endpoint.resource.kind == .application ? "Redeploy now…" : "Restart now…") {
                                    confirmActivation = true
                                }
                                .disabled(model.busy)
                            }
                            Button("Later") { model.changedDestination = nil }
                        }
                    }
                }
                if model.busy { ProgressView() }
            }
            .disabled(model.busy)
            .navigationTitle(model.reviewing ? "Review variable changes" : "Compare and sync")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(model.busy) }
            }
            .confirmationDialog(
                "Apply saved variables to \(model.changedDestination?.label ?? "destination")?",
                isPresented: $confirmActivation, titleVisibility: .visible
            ) {
                if let endpoint = model.changedDestination {
                    Button(endpoint.resource.kind == .application ? "Redeploy" : "Restart") {
                        guard let client = client(for: endpoint) else { return }
                        Task { await model.activate(client: client, endpoint: endpoint) }
                    }
                }
            }
        }
        .interactiveDismissDisabled(model.busy)
        #if os(macOS)
        .frame(minWidth: 640, idealWidth: 740, minHeight: 560, idealHeight: 720)
        #endif
        .onChange(of: source) { _, _ in
            if source?.resource.kind != .application { sourcePreview = false }
            model.reset()
        }
        .onChange(of: destination) { _, _ in
            if destination?.resource.kind != .application { destinationPreview = false }
            model.reset()
        }
        .onChange(of: sourcePreview) { _, _ in model.reset() }
        .onChange(of: destinationPreview) { _, _ in model.reset() }
        .onChange(of: model.changedDestination) { _, endpoint in
            if endpoint != nil && !model.changedPreview { confirmActivation = true }
        }
        .onChange(of: lock.isOpen) { _, open in if !open { model.reset() } }
    }

    @ViewBuilder
    private func comparison(_ plan: VariableSyncPlan) -> some View {
        Section {
            Text("\(source?.label ?? "") → \(destination?.label ?? "")")
            Text("\(sourcePreview ? "Preview" : "Production") → \(destinationPreview ? "Preview" : "Production")").font(
                .caption)
            Text("Shared references are copied as written and resolve in the destination's context.").font(.caption)
            if !model.reviewing {
                Button("Select all source changes") {
                    model.selected = Set(plan.changes.filter { $0.kind == .create || $0.kind == .update }.map(\.key))
                }
                Button("Clear selection") {
                    model.selected = []
                    model.matchDestination = false
                }
                Toggle("Make destination match source, including deletions", isOn: $model.matchDestination)
                    .disabled(plan.changes.contains { $0.kind == .unavailable })
                    .onChange(of: model.matchDestination) { _, match in
                        if match {
                            model.selected = Set(
                                plan.changes.filter { $0.kind == .create || $0.kind == .update }.map(\.key))
                        }
                    }
            }
        }
        Section(model.reviewing ? "Changes to apply" : "Comparison") {
            ForEach(model.reviewing ? model.writes : plan.changes) { change in
                if !model.reviewing, change.kind == .create || change.kind == .update {
                    Toggle(
                        isOn: Binding(
                            get: { model.selected.contains(change.key) },
                            set: { selected in
                                if selected {
                                    model.selected.insert(change.key)
                                } else {
                                    model.selected.remove(change.key)
                                    model.matchDestination = false
                                }
                            })
                    ) { VariableSyncRow(change: change, deleting: false) }
                } else {
                    VariableSyncRow(change: change, deleting: model.matchDestination)
                }
            }
        }
        Section {
            if model.reviewing {
                Button("Apply \(model.writes.count) changes to destination") { Task { await apply() } }
                    .disabled(model.writes.isEmpty || !lock.isOpen)
                Button("Back to selection") { model.reviewing = false }
            } else {
                Button("Review \(model.writes.count) changes…") { model.reviewing = true }
                    .disabled(model.writes.isEmpty)
            }
        }
    }

    private func client(for endpoint: ResourceEndpoint) -> CoolifyClient? {
        store.instances.first { $0.id == endpoint.instanceID }.flatMap { store.client(for: $0) }
    }

    private func compare() async {
        guard lock.isOpen, let source, let destination, let sourceClient = client(for: source),
            let destinationClient = client(for: destination)
        else {
            model.message = "Both instances need an API token."
            return
        }
        await model.compare(
            source: source, destination: destination, sourceClient: sourceClient, destinationClient: destinationClient,
            sourcePreview: sourcePreview, destinationPreview: destinationPreview)
    }

    private func apply() async {
        guard lock.isOpen, let source, let destination, let sourceClient = client(for: source),
            let destinationClient = client(for: destination)
        else { return }
        await model.apply(
            source: source, destination: destination, sourceClient: sourceClient, destinationClient: destinationClient,
            sourcePreview: sourcePreview)
        onChanged()
    }
}

#Preview {
    VariableSyncView(onChanged: {})
        .environment(InstanceStore(instances: []))
        .environment(VariableLock(isRequired: false))
}

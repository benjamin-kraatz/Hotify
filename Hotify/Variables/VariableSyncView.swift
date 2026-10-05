import CoolifyAPI
import SwiftUI

/// Copies variables from one resource to another, on any two instances: pick both ends, compare, choose, review, apply.
struct VariableSyncView: View {
    @SwiftUI.Environment(InstanceStore.self) private var store
    @SwiftUI.Environment(VariableLock.self) private var lock
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @SwiftUI.Environment(\.horizontalSizeClass) private var sizeClass
    @State var source: ResourceEndpoint?
    @State private var destination: ResourceEndpoint?
    @State private var sourcePreview = false
    @State private var destinationPreview = false
    @State private var model = VariableSyncModel()
    @State private var showsIdentical = false
    var onChanged: () -> Void

    private enum Stage {
        case route
        case compare
        case review
    }

    private var stage: Stage {
        guard model.plan != nil else { return .route }
        return model.reviewing ? .review : .compare
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if lock.isOpen {
                        outcome
                        switch stage {
                        case .route:
                            route
                        case .compare:
                            if let plan = model.plan {
                                routeSummary
                                comparison(plan)
                            }
                        case .review:
                            review
                        }
                    } else {
                        LockCard(
                            method: lock.method,
                            failure: lock.failure,
                            isAuthenticating: lock.isAuthenticating,
                            prompt: "Confirm it’s you to compare and copy values."
                        ) {
                            Task { await lock.unlock() }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(model.busy)
            }
            .navigationTitle(stage == .review ? "Review Changes" : "Compare and Sync")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
        }
        .interactiveDismissDisabled(model.busy)
        #if os(macOS)
        .frame(minWidth: 640, idealWidth: 740, minHeight: 560, idealHeight: 720)
        #endif
        .animation(.snappy, value: stage)
        .animation(.snappy, value: model.message)
        .animation(.snappy, value: model.changedDestination)
        .animation(.snappy, value: lock.isOpen)
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
        .onChange(of: lock.isOpen) { _, open in if !open { model.reset() } }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if stage == .review {
                Button("Back") { model.reviewing = false }
                    .disabled(model.busy)
            } else {
                Button("Done") { dismiss() }
                    .disabled(model.busy)
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            if model.busy {
                ProgressView()
                    .controlSize(.small)
            } else if lock.isOpen {
                switch stage {
                case .route:
                    Button("Compare") { Task { await compare() } }
                        .disabled(source == nil || destination == nil)
                        .keyboardShortcut(.defaultAction)
                case .compare:
                    Button("Review…") { model.reviewing = true }
                        .disabled(model.writes.isEmpty)
                        .keyboardShortcut(.defaultAction)
                case .review:
                    // No default shortcut. Return should not write to another instance.
                    Button("Apply") { Task { await apply() } }
                        .disabled(model.writes.isEmpty)
                }
            }
        }
    }

    // MARK: Outcome

    /// What the last compare or apply came to, and the restart that puts saved variables to use.
    @ViewBuilder
    private var outcome: some View {
        if let message = model.message {
            if model.messageIsGood {
                SavedBanner(message: message)
            } else {
                NoticeBanner(message: message)
            }
        }
        if let endpoint = model.changedDestination {
            let action: ResourceAction = endpoint.resource.kind == .application ? .deploy : .restart
            ApplyBar(
                kind: endpoint.resource.kind,
                message: model.changedPreview
                    ? "Redeploy the affected previews in Coolify to use the new variables."
                    : "\(endpoint.resource.name) picks these up after a \(action == .deploy ? "redeploy" : "restart").",
                action: model.changedPreview ? nil : action,
                isBusy: model.busy,
                onApply: { _ in
                    guard let client = client(for: endpoint) else { return }
                    Task { await model.activate(client: client, endpoint: endpoint) }
                },
                onDismiss: { model.changedDestination = nil }
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: Route

    private var route: some View {
        // A phone stacks the two ends. One layout value keeps each picker's state across a rotation.
        let isStacked = sizeClass == .compact
        let layout = isStacked ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return VStack(alignment: .leading, spacing: 14) {
            layout {
                SyncEndpointCard(title: "Copy from", endpoint: $source, isPreview: $sourcePreview)
                Button("Swap Direction", systemImage: isStacked ? "arrow.up.arrow.down" : "arrow.left.arrow.right") {
                    swap(&source, &destination)
                    swap(&sourcePreview, &destinationPreview)
                }
                .labelStyle(.iconOnly)
                .glassButton()
                .help("Swap the two ends")
                SyncEndpointCard(title: "Copy to", endpoint: $destination, isPreview: $destinationPreview)
            }
            .fixedSize(horizontal: false, vertical: true)

            Text("Comparing only reads. Nothing on either side changes until you review the list and apply it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Both ends once a comparison is up, with the way back to change them.
    private var routeSummary: some View {
        HStack(spacing: 12) {
            // Side by side when the names fit. A phone puts the destination under the source.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { ends(arrow: "arrow.right") }
                VStack(alignment: .leading, spacing: 8) { ends(arrow: "arrow.down") }
            }
            Spacer(minLength: 8)
            Button("Change") { model.reset() }
                .buttonStyle(.borderless)
                .help("Pick other resources. This drops the comparison.")
        }
        .padding(14)
        .well()
    }

    @ViewBuilder
    private func ends(arrow: String) -> some View {
        if let source {
            end(source, isPreview: sourcePreview)
        }
        Image(systemName: arrow)
            .font(.body.weight(.semibold))
            .foregroundStyle(.ember)
            .accessibilityLabel("copies to")
        if let destination {
            end(destination, isPreview: destinationPreview)
        }
    }

    /// What to call the destination in a heading. Two resources often share a name across instances.
    private var destinationName: String {
        guard let source, let destination else { return "the destination" }
        if source.resource.name != destination.resource.name {
            return destination.resource.name
        }
        if source.instanceID != destination.instanceID {
            return "\(destination.resource.name) on \(destination.instanceName)"
        }
        return destinationPreview ? "the preview variables" : "the production variables"
    }

    private func end(_ endpoint: ResourceEndpoint, isPreview: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(endpoint.resource.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if endpoint.resource.kind == .application {
                    Chip(text: isPreview ? "Preview" : "Production")
                }
            }
            Text(endpoint.instanceName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Comparison

    @ViewBuilder
    private func comparison(_ plan: VariableSyncPlan) -> some View {
        let creates = plan.changes.filter { $0.kind == .create }
        let updates = plan.changes.filter { $0.kind == .update }
        let extras = plan.changes.filter { $0.kind == .destinationOnly }
        let withheld = plan.changes.filter { $0.kind == .unavailable }
        let identical = plan.changes.filter { $0.kind == .unchanged }

        if creates.isEmpty, updates.isEmpty, extras.isEmpty, withheld.isEmpty {
            ContentUnavailableView {
                Label {
                    Text("Already in sync")
                } icon: {
                    FlameGlyph(heat: .lit, height: 40, ignitesOnAppear: true)
                }
            } description: {
                Text(
                    identical.isEmpty
                        ? "Neither side has any variables."
                        : "Both sides hold the same \(Self.count(identical.count, of: "variable"))."
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            if !model.selectable.isEmpty {
                HStack(spacing: 14) {
                    Text("\(model.selected.count) of \(model.selectable.count) picked to copy")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    Spacer(minLength: 8)
                    Button("Pick All") { model.selected = model.selectable }
                        .disabled(model.selected == model.selectable)
                    Button("Pick None") {
                        model.selected = []
                        model.matchDestination = false
                    }
                    .disabled(model.selected.isEmpty && !model.matchDestination)
                }
                .buttonStyle(.borderless)
            }

            if !creates.isEmpty {
                group("Missing in \(destinationName)", creates)
            }
            if !updates.isEmpty {
                group("Different", updates)
            }
            if !extras.isEmpty {
                group("Only in \(destinationName)", extras) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delete these to match the source")
                            Group {
                                if !withheld.isEmpty {
                                    Text("Not possible while Coolify withholds some source values.")
                                } else if !model.selectable.isEmpty {
                                    Text("Also picks every difference above.")
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Toggle(
                            "Delete these to match the source",
                            isOn: Binding(
                                get: { model.matchDestination },
                                set: { match in
                                    model.matchDestination = match
                                    if match { model.selected = model.selectable }
                                })
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(.glow)
                        .disabled(!withheld.isEmpty)
                    }
                }
            }
            if !withheld.isEmpty {
                group("Cannot copy", withheld) {
                    Text(
                        "Coolify does not send these values back, either because they were saved as hidden or because the token lacks read:sensitive. Set them by hand on the destination."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        if !identical.isEmpty, identical.count != plan.changes.count {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    showsIdentical.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Text("\(identical.count) already the same")
                            .font(.headline)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(showsIdentical ? 90 : 0))
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityValue(showsIdentical ? "Expanded" : "Collapsed")

                if showsIdentical {
                    rows(identical)
                        .transition(.opacity)
                }
            }
            .animation(.snappy, value: showsIdentical)
        }
    }

    private func group(_ title: String, _ changes: [VariableSyncChange]) -> some View {
        group(title, changes) { EmptyView() }
    }

    private func group<Note: View>(
        _ title: String, _ changes: [VariableSyncChange], @ViewBuilder note: () -> Note
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            note()
            rows(changes)
        }
    }

    private func rows(_ changes: [VariableSyncChange]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(changes.enumerated()), id: \.element.id) { index, change in
                if index > 0 {
                    Divider()
                        .padding(.leading, 14)
                }
                row(change)
            }
        }
        .well()
    }

    @ViewBuilder
    private func row(_ change: VariableSyncChange) -> some View {
        if stage == .compare, change.kind == .create || change.kind == .update {
            VariableSyncRow(change: change, isSelected: model.selected.contains(change.key), deleting: false)
                .onTapGesture { toggle(change.key) }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { toggle(change.key) }
        } else {
            VariableSyncRow(change: change, isSelected: nil, deleting: model.matchDestination)
        }
    }

    private func toggle(_ key: String) {
        if model.selected.contains(key) {
            model.selected.remove(key)
            // With a difference left out, the destination no longer matches.
            model.matchDestination = false
        } else {
            model.selected.insert(key)
        }
    }

    // MARK: Review

    private var review: some View {
        let deletions = model.writes.filter { $0.kind == .destinationOnly }.count
        return VStack(alignment: .leading, spacing: 14) {
            routeSummary
            VStack(alignment: .leading, spacing: 6) {
                Text("\(Self.count(model.writes.count)) to \(destinationName)")
                    .font(.title3.weight(.semibold))
                Text(
                    "Shared references such as {{team.API_URL}} are copied as written and resolve on the destination."
                        + (deletions > 0 ? " Coolify deletes \(Self.count(deletions, of: "variable")) for good." : "")
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            rows(model.writes)
        }
    }

    // MARK: Actions

    private static func count(_ count: Int, of noun: String = "change") -> String {
        count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }

    private func client(for endpoint: ResourceEndpoint) -> CoolifyClient? {
        store.instances.first { $0.id == endpoint.instanceID }.flatMap { store.client(for: $0) }
    }

    private func compare() async {
        guard lock.isOpen, let source, let destination, let sourceClient = client(for: source),
            let destinationClient = client(for: destination)
        else {
            model.messageIsGood = false
            model.message = "Both instances need an API token."
            return
        }
        showsIdentical = false
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

/// An inline message for a write or an action that went through. Ember, where `NoticeBanner` is amber.
private struct SavedBanner: View {
    var message: String

    var body: some View {
        Label {
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.ember)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ember.opacity(0.08), in: .rect(cornerRadius: 12))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

#Preview {
    VariableSyncView(onChanged: {})
        .environment(InstanceStore(instances: []))
        .environment(VariableLock(isRequired: false))
}

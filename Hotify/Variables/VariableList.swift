import CoolifyAPI
import SwiftUI

/// A resource's environment variables. Keys always show. Values wait until `VariableLock` opens.
struct VariableList: View {
    @SwiftUI.Environment(InstanceStore.self) private var store
    @SwiftUI.Environment(VariableLock.self) private var lock
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    var model: VariablesModel
    var resource: ResourceSummary
    var pendingAction: ResourceAction?
    var onAction: (ResourceAction) -> Void

    @State private var filter = ""
    @State private var editing: EditorTarget?
    @State private var deleting: VariableLine?
    @State private var copiedAll = 0
    @State private var syncing = false

    private var shown: [VariableLine] {
        let trimmed = filter.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return model.variables }
        return model.variables.filter { $0.key.localizedStandardContains(trimmed) }
    }

    /// A token without the `read:sensitive` ability gets keys but no values, even for variables not marked hidden.
    private var isTokenMissingValues: Bool {
        model.variables.contains { $0.value == nil && !$0.isShownOnce }
    }

    /// What puts a change to use. A stopped resource picks it up when it starts, so it needs nothing.
    private var applyAction: ResourceAction? {
        guard resource.heat != .cold, !model.lastChangeWasPreview else { return nil }
        return resource.kind == .application ? .deploy : .restart
    }

    private var unlockAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.45)
    }

    var body: some View {
        VStack(spacing: 10) {
            controls
            notices
            if !lock.isOpen, !model.variables.isEmpty {
                LockCard(method: lock.method, failure: lock.failure, isAuthenticating: lock.isAuthenticating) {
                    Task { await unlock() }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            list
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .animation(unlockAnimation, value: lock.isOpen)
        .animation(.snappy, value: model.hasUnappliedChanges)
        .animation(.snappy, value: model.writeError)
        .animation(.snappy, value: model.loadError)
        .task(id: model.owner) {
            await model.load()
        }
        .sheet(item: $editing) { target in
            editor(for: target)
        }
        .sheet(isPresented: $syncing) {
            VariableSyncView(
                source: store.selected.map {
                    ResourceEndpoint(instanceID: $0.id, instanceName: $0.name, resource: resource)
                }
            ) {
                Task { await model.load() }
            }
        }
        .confirmationDialog(
            deleting.map { "Delete \($0.key)?" } ?? "",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { line in
            Button("Delete", role: .destructive) {
                Task { await model.delete(line) }
            }
        } message: { _ in
            Text(
                "Coolify removes it from \(resource.name) for good. Running containers keep the old value until they restart."
            )
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(.secondary)
                TextField("Filter keys", text: $filter)
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

            if lock.isRequired, lock.isOpen, let until = lock.unlockedUntil {
                Button {
                    lock.lock()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.open.fill")
                            .foregroundStyle(.ember)
                        Text(timerInterval: Date.now...max(until, .now), countsDown: true)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("Values lock again at \(until.formatted(date: .omitted, time: .shortened)). Click to lock now.")
                .accessibilityLabel("Lock values")
                .transition(.opacity)
            }

            Button {
                Task {
                    guard await unlock() else { return }
                    syncing = true
                }
            } label: {
                Label("Compare and Sync", systemImage: "arrow.left.arrow.right")
            }
            .labelStyle(.iconOnly)
            .help("Compare these variables with another resource and copy the differences")

            Menu {
                Button("Copy All as .env", systemImage: "doc.on.clipboard") {
                    copyAll()
                }
                .disabled(!lock.isOpen || shown.allSatisfy { $0.value == nil })
                Button("Reload", systemImage: "arrow.clockwise") {
                    Task { await model.load() }
                }
                #if os(macOS)
                Divider()
                SettingsLink {
                    Label("Lock Settings…", systemImage: "gear")
                }
                #endif
            } label: {
                Label("More", systemImage: copiedAll > 0 ? "checkmark" : "ellipsis.circle")
                    .contentTransition(.symbolEffect(.replace))
            }
            .labelStyle(.iconOnly)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Copy and reload")
            .task(id: copiedAll) {
                guard copiedAll > 0 else { return }
                try? await Task.sleep(for: .seconds(1.5))
                copiedAll = 0
            }

            Button {
                Task { await edit(.new) }
            } label: {
                Label("Add Variable", systemImage: "plus")
            }
            .labelStyle(.iconOnly)
            .help("Add a variable")
        }
        .buttonStyle(.borderless)
        .controlSize(.regular)
    }

    @ViewBuilder
    private var notices: some View {
        if let error = model.loadError {
            NoticeBanner(message: error)
        }
        if let error = model.writeError {
            NoticeBanner(message: error)
        }
        if lock.isOpen, isTokenMissingValues {
            NoticeBanner(
                message:
                    "This API token cannot read values. Give it the read:sensitive permission under Keys & Tokens in Coolify.",
                systemImage: "key.fill"
            )
        }
        if model.hasUnappliedChanges {
            ApplyBar(
                kind: resource.kind,
                message: applyMessage,
                action: applyAction,
                isBusy: pendingAction != nil || resource.isDeploying,
                onApply: { action in
                    onAction(action)
                    model.hasUnappliedChanges = false
                },
                onDismiss: { model.hasUnappliedChanges = false }
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var applyMessage: String {
        if model.lastChangeWasPreview {
            return "Saved. Redeploy the affected previews in Coolify to apply these variables."
        }
        return switch applyAction {
        case .deploy: "Saved. It takes effect after a redeploy."
        case .restart: "Saved. It takes effect after a restart."
        default: "Saved. It takes effect on the next start."
        }
    }

    // MARK: List

    private var list: some View {
        let production = shown.filter { !$0.isPreview }
        let previews = shown.filter(\.isPreview)
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !production.isEmpty {
                    section(previews.isEmpty ? nil : "Production", production)
                }
                if !previews.isEmpty {
                    section("Preview Deployments", previews)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable {
            await model.load()
        }
        .overlay {
            if model.variables.isEmpty {
                if model.isLoading || (!model.hasLoaded && model.loadError == nil && model.owner != nil) {
                    ProgressView()
                } else if model.loadError == nil {
                    ContentUnavailableView {
                        Label("No variables", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("\(resource.name) has no environment variables. Add one to hand it a setting or a secret.")
                    } actions: {
                        Button("Add Variable") {
                            Task { await edit(.new) }
                        }
                        .glassButton(prominent: true)
                    }
                }
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: filter)
            }
        }
        .animation(.snappy, value: model.variables)
    }

    private func section(_ title: String?, _ lines: [VariableLine]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 14)
                    }
                    row(line)
                }
            }
            .background(Color.primary.opacity(0.045), in: .rect(cornerRadius: 14))
        }
    }

    private func row(_ line: VariableLine) -> some View {
        VariableRow(line: line, isOpen: lock.isOpen) { SecretPasteboard.copy($0) }
            .onTapGesture {
                Task { await edit(.existing(line)) }
            }
            .accessibilityAction(named: lock.isOpen ? "Edit" : "Unlock") {
                Task { await edit(.existing(line)) }
            }
            .contextMenu {
                if lock.isOpen {
                    if let value = line.value {
                        Button("Copy Value", systemImage: "doc.on.doc") {
                            SecretPasteboard.copy(value)
                        }
                    }
                    if let dotenv = line.dotenvLine {
                        Button("Copy as KEY=value", systemImage: "equal.square") {
                            SecretPasteboard.copy(dotenv)
                        }
                    }
                } else {
                    Button("Unlock Values", systemImage: lock.method.systemImage) {
                        Task { await unlock() }
                    }
                }
                Button("Copy Key", systemImage: "key") {
                    SecretPasteboard.copy(line.key)
                }
                Divider()
                Button("Edit…", systemImage: "pencil") {
                    Task { await edit(.existing(line)) }
                }
                Button("Delete…", systemImage: "trash", role: .destructive) {
                    Task {
                        guard await unlock() else { return }
                        deleting = line
                    }
                }
            }
    }

    // MARK: Actions

    @discardableResult
    private func unlock() async -> Bool {
        await lock.unlock()
    }

    /// Opens the editor, asking to unlock first. Tapping a locked row is the quickest way to see its value.
    private func edit(_ target: EditorTarget) async {
        guard await unlock() else { return }
        editing = target
    }

    private func copyAll() {
        let lines = shown.compactMap(\.dotenvLine)
        guard !lines.isEmpty else { return }
        SecretPasteboard.copy(lines.joined(separator: "\n") + "\n")
        copiedAll += 1
    }

    private func editor(for target: EditorTarget) -> some View {
        let original: VariableLine? =
            switch target {
            case .new: nil
            case .existing(let line): line
            }
        return VariableEditor(
            original: original,
            kind: resource.kind,
            takenKeys: { isPreview in
                Set(model.variables.filter { $0.isPreview == isPreview }.map(\.key))
            },
            onSave: { draft in
                try await model.save(draft, isNew: original == nil)
            },
            onDelete: original.map { line in
                { Task { await model.delete(line) } }
            }
        )
    }
}

/// Which variable the editor sheet opens on.
private enum EditorTarget: Identifiable {
    case new
    case existing(VariableLine)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let line): line.id
        }
    }
}

#Preview("Locked") {
    variableListPreview(isRequired: true)
}

#Preview("Open") {
    variableListPreview(isRequired: false, unapplied: true)
}

#Preview("Empty") {
    let model = VariablesModel()
    model.hasLoaded = true
    return VariableList(
        model: model,
        resource: ResourceSummary(route: .database("db"), name: "postgres", status: "running:healthy"),
        onAction: { _ in }
    )
    .environment(InstanceStore(instances: []))
    .environment(VariableLock(isRequired: true))
    .frame(width: 560, height: 420)
}

private func variableListPreview(isRequired: Bool, unapplied: Bool = false) -> some View {
    let model = VariablesModel()
    model.hasLoaded = true
    model.hasUnappliedChanges = unapplied
    model.variables = [
        VariableLine(id: "1", key: "DATABASE_URL", value: "postgres://app:secret@db:5432/app"),
        VariableLine(
            id: "2",
            key: "API_URL",
            value: "{{project.API_URL}}",
            resolvedValue: "https://api.example.com"
        ),
        VariableLine(id: "3", key: "NODE_ENV", value: "production", isLiteral: true),
        VariableLine(id: "4", key: "STRIPE_SECRET_KEY", isShownOnce: true),
        VariableLine(id: "5", key: "API_URL", value: "https://pr.api.example.com", isPreview: true),
    ]
    return VariableList(
        model: model,
        resource: ResourceSummary(route: .application("app"), name: "marketing-site", status: "running:healthy"),
        onAction: { _ in }
    )
    .environment(InstanceStore(instances: []))
    .environment(VariableLock(isRequired: isRequired))
    .frame(width: 560, height: 560)
}

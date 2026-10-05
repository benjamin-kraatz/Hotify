import CoolifyAPI
import SwiftUI

/// The variables one or more scopes share with their resources. Keys always show. Values wait until
/// `VariableLock` opens, as they do for a resource.
struct SharedVariableList: View {
    @SwiftUI.Environment(VariableLock.self) private var lock
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    var model: SharedVariablesModel
    /// Names the project in a project-scoped caption. A team or a server does not have one.
    var projectName: String? = nil

    @State private var filter = ""
    @State private var editing: EditorTarget?
    @State private var deleting: DeleteTarget?

    private var shown: [SharedVariableSection] {
        let trimmed = filter.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return model.sections }
        return model.sections.compactMap { section in
            var section = section
            section.lines = section.lines.filter { $0.key.localizedStandardContains(trimmed) }
            return section.lines.isEmpty ? nil : section
        }
    }

    /// A token without the `read:sensitive` ability gets keys but no values, even for variables not marked hidden.
    private var isTokenMissingValues: Bool {
        model.sections.contains { $0.lines.contains { $0.value == nil && !$0.isShownOnce } }
    }

    private var unlockAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.45)
    }

    var body: some View {
        VStack(spacing: 10) {
            controls
            notices
            if !lock.isOpen, !model.isEmpty {
                LockCard(method: lock.method, failure: lock.failure, isAuthenticating: lock.isAuthenticating) {
                    Task { await lock.unlock() }
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
        // Reloads when an environment joins or leaves the project, as well as when the tab opens.
        .task(id: model.sections.map(\.scope)) {
            await model.load()
        }
        .sheet(item: $editing) { target in
            editor(for: target)
        }
        .confirmationDialog(
            deleting.map { "Delete \($0.line.key)?" } ?? "",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { target in
            Button("Delete", role: .destructive) {
                Task { await model.delete(target.line, in: target.scope) }
            }
        } message: { _ in
            Text(
                "Coolify removes it for good. A resource that refers to it loses the value the next time it is deployed."
            )
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 10) {
            FilterField("Filter keys", text: $filter)

            LockCountdownButton(lock: lock)

            Menu {
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
                Label("More", systemImage: "ellipsis.circle")
            }
            .labelStyle(.iconOnly)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Reload")
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
                kind: .application,
                message: "Saved. A resource that refers to it picks up the change the next time it is deployed.",
                action: nil,
                isBusy: false,
                onApply: { _ in },
                onDismiss: { model.hasUnappliedChanges = false }
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: List

    private var list: some View {
        let shown = shown
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Until the first load answers, an empty section would claim there are no variables.
                if model.hasLoaded {
                    ForEach(shown) { section in
                        self.section(section)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable {
            await model.load()
        }
        .overlay {
            if !model.hasLoaded {
                if model.loadError == nil {
                    ProgressView()
                }
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: filter)
            }
        }
        .animation(.snappy, value: model.sections)
        .animation(.snappy, value: shown.map(\.id))
    }

    private func section(_ section: SharedVariableSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(caption(for: section))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button {
                    Task { await edit(.new(section.scope)) }
                } label: {
                    Label("Add Variable to \(section.title)", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help(addHelp(for: section))
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                if section.lines.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No shared variables yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button {
                            Task { await edit(.new(section.scope)) }
                        } label: {
                            Label("Add Variable", systemImage: "plus")
                        }
                        .glassButton()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
                ForEach(Array(section.lines.enumerated()), id: \.element.id) { index, line in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 14)
                    }
                    row(line, in: section)
                }
            }
            .well()
        }
    }

    private func addHelp(for section: SharedVariableSection) -> String {
        switch section.scope {
        case .project: "Add a variable for the whole project"
        case .environment: "Add a variable for \(section.title)"
        case .team: "Add a variable for the team"
        case .server: "Add a variable for \(section.title)"
        }
    }

    private func caption(for section: SharedVariableSection) -> String {
        switch section.scope {
        case .project:
            "Every resource in \(projectName ?? "this project") can use these, as \(section.reference(to: "KEY"))."
        case .environment:
            "Resources in \(section.title) can use these, as \(section.reference(to: "KEY"))."
        case .team:
            "Every resource in this team can use these, as \(section.reference(to: "KEY"))."
        case .server:
            "Resources on \(section.title) can use these, as \(section.reference(to: "KEY"))."
        }
    }

    private func row(_ line: VariableLine, in section: SharedVariableSection) -> some View {
        VariableRow(line: line, isOpen: lock.isOpen) { SecretPasteboard.copy($0) }
            .onTapGesture {
                Task { await edit(.existing(line, section.scope)) }
            }
            .accessibilityAction(named: lock.isOpen ? "Edit" : "Unlock") {
                Task { await edit(.existing(line, section.scope)) }
            }
            .contextMenu {
                // What a resource's own variable is set to in order to read this one.
                Button("Copy Reference", systemImage: "curlybraces") {
                    SecretPasteboard.copy(section.reference(to: line.key))
                }
                Button("Copy Key", systemImage: "key") {
                    SecretPasteboard.copy(line.key)
                }
                if lock.isOpen {
                    if let value = line.value {
                        Button("Copy Value", systemImage: "doc.on.doc") {
                            SecretPasteboard.copy(value)
                        }
                    }
                } else {
                    Button("Unlock Values", systemImage: lock.method.systemImage) {
                        Task { await lock.unlock() }
                    }
                }
                Divider()
                Button("Edit…", systemImage: "pencil") {
                    Task { await edit(.existing(line, section.scope)) }
                }
                Button("Delete…", systemImage: "trash", role: .destructive) {
                    Task {
                        guard await lock.unlock() else { return }
                        deleting = DeleteTarget(line: line, scope: section.scope)
                    }
                }
            }
    }

    // MARK: Actions

    /// Opens the editor, asking to unlock first. Tapping a locked row is the quickest way to see its value.
    private func edit(_ target: EditorTarget) async {
        guard await lock.unlock() else { return }
        editing = target
    }

    private func editor(for target: EditorTarget) -> some View {
        let scope = target.scope
        let original = target.line
        return VariableEditor(
            original: original,
            hasPreviewVariables: false,
            takenKeys: { _ in
                Set(model.sections.first { $0.scope == scope }?.lines.map(\.key) ?? [])
            },
            onSave: { draft in
                try await model.save(draft, replacing: original, in: scope)
            },
            onDelete: original.map { line in
                { Task { await model.delete(line, in: scope) } }
            }
        )
    }
}

/// Which variable the editor sheet opens on, and the scope it belongs to.
private enum EditorTarget: Identifiable {
    case new(SharedVariableScope)
    case existing(VariableLine, SharedVariableScope)

    var id: String {
        switch self {
        case .new(let scope): "new-\(scope.hashValue)"
        case .existing(let line, let scope): "\(line.id)-\(scope.hashValue)"
        }
    }

    var scope: SharedVariableScope {
        switch self {
        case .new(let scope), .existing(_, let scope): scope
        }
    }

    var line: VariableLine? {
        switch self {
        case .new: nil
        case .existing(let line, _): line
        }
    }
}

/// The variable a delete confirmation is about.
private struct DeleteTarget {
    var line: VariableLine
    var scope: SharedVariableScope
}

#Preview("Locked") {
    sharedVariablePreview(isRequired: true)
}

#Preview("Open") {
    sharedVariablePreview(isRequired: false)
}

private func sharedVariablePreview(isRequired: Bool) -> some View {
    SharedVariableList(
        model: SharedVariablesModel(
            sections: [
                SharedVariableSection(
                    scope: .project("website"),
                    title: "Project",
                    lines: [
                        VariableLine(id: "1", key: "API_URL", value: "https://api.example.com", isLiteral: true),
                        VariableLine(id: "2", key: "STRIPE_SECRET_KEY", isShownOnce: true),
                    ]
                ),
                SharedVariableSection(
                    scope: .environment(project: "website", environment: "production"),
                    title: "production",
                    lines: [VariableLine(id: "3", key: "LOG_LEVEL", value: "warn", comment: "Quiet in production")]
                ),
                SharedVariableSection(
                    scope: .environment(project: "website", environment: "staging"), title: "staging"),
            ],
            hasLoaded: true
        ),
        projectName: "Website"
    )
    .environment(VariableLock(isRequired: isRequired))
    .frame(width: 560, height: 560)
}

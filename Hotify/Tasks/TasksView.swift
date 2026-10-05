import CoolifyAPI
import SwiftUI

/// An application's or service's scheduled commands: each one's schedule, and the runs of the one you select.
struct TasksView: View {
    var client: CoolifyClient?
    var uuid: String
    var kind: ResourceKind

    @State private var model: TasksModel
    @State private var selectedUUID: String?
    @State private var editing: EditorTarget?
    @State private var deleting: ScheduledTask?
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        client: CoolifyClient?,
        uuid: String,
        kind: ResourceKind,
        selection: String? = nil,
        model: TasksModel = TasksModel()
    ) {
        self.client = client
        self.uuid = uuid
        self.kind = kind
        _model = State(initialValue: model)
        _selectedUUID = State(initialValue: selection)
    }

    private var owner: ScheduledTaskOwner? {
        switch kind {
        case .application: .application(uuid)
        case .service: .service(uuid)
        case .database: nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let error = model.loadError {
                    NoticeBanner(message: error)
                }
                if let error = model.writeError {
                    NoticeBanner(message: error)
                }
                if model.hasLoaded, !model.tasks.isEmpty {
                    addButton
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    taskList
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay { emptyState }
        .animation(reduceMotion ? nil : .snappy, value: selectedUUID)
        .animation(.snappy, value: model.loadError)
        .animation(.snappy, value: model.writeError)
        .animation(.snappy, value: model.tasks.map(\.uuid))
        .refreshable {
            if client != nil {
                await model.refresh()
            }
        }
        .task(id: owner) { await follow() }
        .onChange(of: model.tasks.map(\.uuid)) { _, ids in
            if let selectedUUID, !ids.contains(selectedUUID) {
                self.selectedUUID = nil
            }
        }
        .task(id: selectedUUID) {
            guard let selectedUUID else {
                model.stopWatchingExecutions()
                return
            }
            await model.loadExecutions(selectedUUID)
        }
        .sheet(item: $editing) { target in
            TaskEditor(task: target.task) { draft in
                try await model.save(draft, updating: target.task?.uuid)
            }
        }
        .confirmationDialog(
            deleting.map { "Delete \($0.name)?" } ?? "",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { task in
            Button("Delete", role: .destructive) {
                if selectedUUID == task.uuid {
                    selectedUUID = nil
                }
                Task { await model.delete(task) }
            }
        } message: { _ in
            Text("Coolify removes this schedule. It does not keep the task's runs once the task is gone.")
        }
    }

    private var addButton: some View {
        Button("Add Task", systemImage: "plus") {
            editing = .new
        }
        .disabled(client == nil || owner == nil)
        .help("Schedule a command")
    }

    private var taskList: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.tasks.enumerated()), id: \.element.uuid) { index, task in
                if index > 0 {
                    Divider()
                        .padding(.leading, 14)
                }
                TaskRow(
                    task: task,
                    isSelected: selectedUUID == task.uuid,
                    isRunning: model.isRunning(task),
                    canAct: client != nil,
                    onSelect: {
                        selectedUUID = selectedUUID == task.uuid ? nil : task.uuid
                    },
                    onEdit: { editing = .edit(task) },
                    onDelete: { deleting = task },
                    onRun: {
                        selectedUUID = task.uuid
                        Task { await model.run(task) }
                    }
                )
                if selectedUUID == task.uuid {
                    TaskExecutionList(
                        executions: model.executions,
                        isLoading: model.isLoadingExecutions,
                        error: model.executionError
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .transition(.opacity)
                }
            }
        }
        .well()
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.isLoading, !model.hasLoaded {
            ProgressView()
        } else if model.tasks.isEmpty, model.hasLoaded || client == nil {
            ContentUnavailableView {
                Label("No scheduled tasks", systemImage: "clock")
            } description: {
                Text("Run a command on a schedule. Pick hourly, daily, weekly, monthly, or type a cron expression.")
            } actions: {
                Button("Add Task", systemImage: "plus") {
                    editing = .new
                }
                .glassButton(prominent: true)
                .disabled(client == nil || owner == nil)
            }
        }
    }

    private func follow() async {
        guard let client, let owner else { return }
        model.prepare(client, owner: owner)
        while !Task.isCancelled {
            await model.refresh()
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
        }
    }
}

private enum EditorTarget: Identifiable {
    case new
    case edit(ScheduledTask)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let task): task.uuid
        }
    }

    var task: ScheduledTask? {
        switch self {
        case .new: nil
        case .edit(let task): task
        }
    }
}

private struct TaskRow: View {
    var task: ScheduledTask
    var isSelected: Bool
    var isRunning: Bool
    var canAct: Bool
    var onSelect: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onRun: () -> Void

    private var containerName: String? {
        guard let container = task.container?.trimmingCharacters(in: .whitespacesAndNewlines), !container.isEmpty
        else { return nil }
        return container
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button(action: onSelect) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(task.command)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])

                Button(isRunning ? "Running…" : "Run Now", action: onRun)
                    .buttonStyle(.borderless)
                    .disabled(!canAct || isRunning)
                    .help("Run this command once, now")

                Button("Edit", systemImage: "pencil", action: onEdit)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(!canAct)
                    .help("Edit this task")

                Button("Delete", systemImage: "trash", action: onDelete)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(!canAct)
                    .help("Delete this task")
            }

            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Text(TaskFrequency.label(for: task.frequency))
                    Text(task.enabled ? "On" : "Off")
                    if let containerName {
                        Text(containerName)
                            .font(.caption.monospaced())
                    }
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(isSelected ? Color.primary.opacity(0.06) : Color.clear)
    }
}

#Preview("Tasks") {
    let model = TasksModel()
    model.tasks = [
        ScheduledTask(
            uuid: "task-1",
            enabled: true,
            name: "Clear cache",
            command: "php artisan cache:clear",
            frequency: "hourly",
            container: "worker"
        ),
        ScheduledTask(
            uuid: "task-2",
            enabled: false,
            name: "Weekly report",
            command: "php artisan report:send",
            frequency: "0 9 * * 1"
        ),
    ]
    model.executions = [
        ScheduledTaskExecution(
            uuid: "run-1",
            status: "failed",
            message: "php: command not found",
            startedAt: "2026-10-05T12:00:00Z"
        ),
        ScheduledTaskExecution(
            uuid: "run-2",
            status: "success",
            duration: 4,
            startedAt: "2026-10-05T11:00:00Z"
        ),
    ]
    model.hasLoaded = true
    return TasksView(client: nil, uuid: "app", kind: .application, selection: "task-1", model: model)
        .frame(width: 640, height: 560)
}

#Preview("Empty") {
    let model = TasksModel()
    model.hasLoaded = true
    return TasksView(client: nil, uuid: "app", kind: .application, model: model)
        .frame(width: 640, height: 420)
}

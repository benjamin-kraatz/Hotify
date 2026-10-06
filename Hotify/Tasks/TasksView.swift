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
                    listHeader
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

    private var enabledCount: Int { model.tasks.count(where: \.enabled) }

    private var listHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(
                enabledCount == model.tasks.count
                    ? (model.tasks.count == 1 ? "1 task" : "\(model.tasks.count) tasks")
                    : "\(enabledCount) of \(model.tasks.count) on"
            )
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
            Spacer()
            Button("Add Task", systemImage: "plus") {
                editing = .new
            }
            .glassButton()
            .disabled(client == nil || owner == nil)
            .help("Schedule a command")
        }
        .animation(.snappy, value: enabledCount)
    }

    private var taskList: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.tasks.enumerated()), id: \.element.uuid) { index, task in
                if index > 0 {
                    Divider()
                        .padding(.leading, 52)
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
                    .padding(.leading, 52)
                    .padding(.trailing, 14)
                    .padding(.bottom, 14)
                    .transition(.asymmetric(insertion: .push(from: .top), removal: .opacity))
                }
            }
        }
        .well()
        .heatEdge(isActive: model.tasks.contains { model.isRunning($0) })
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.isLoading, !model.hasLoaded {
            Kindling(caption: "Loading tasks…")
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

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: 12) {
                    TaskMark(isEnabled: task.enabled, isRunning: isRunning)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(task.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(task.enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                        Text(task.command)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(isSelected ? 3 : 1)
                            .truncationMode(.middle)
                        HStack(spacing: 6) {
                            Label(TaskFrequency.label(for: task.frequency), systemImage: "clock")
                                .labelStyle(.titleAndIcon)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(task.enabled ? AnyShapeStyle(.core) : AnyShapeStyle(.secondary))
                            if !task.enabled {
                                Chip(text: "Off")
                            }
                            if let containerName {
                                Chip(text: containerName)
                            }
                        }
                        .padding(.top, 1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isSelected ? 90 : 0))
                        .padding(.top, 4)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityHint(isSelected ? "Hides this task's runs" : "Shows this task's runs")

            Button(action: onRun) {
                Label(isRunning ? "Running…" : "Run Now", systemImage: "play.fill")
                    .contentTransition(.interpolate)
            }
            .glassButton()
            .controlSize(.small)
            .disabled(!canAct || isRunning)
            .help("Run this command once, now")

            Menu {
                Button("Edit Task…", systemImage: "pencil", action: onEdit)
                Button("Delete Task…", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Label("Task actions", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuIndicator(.hidden)
            .buttonStyle(.borderless)
            .fixedSize()
            .disabled(!canAct)
            .help("Edit or delete this task")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(isSelected ? 0.04 : (isHovered ? 0.025 : 0)))
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Run Now", systemImage: "play.fill", action: onRun)
                .disabled(!canAct || isRunning)
            Button("Edit Task…", systemImage: "pencil", action: onEdit)
                .disabled(!canAct)
            Divider()
            Button("Delete Task…", systemImage: "trash", role: .destructive, action: onDelete)
                .disabled(!canAct)
        }
        .animation(.snappy(duration: 0.15), value: isHovered)
        .animation(.snappy, value: isRunning)
    }
}

/// A task's mark: a clock while it waits for its schedule, a pause when it is off, and a flickering flame while a
/// run Hotify asked for is in flight.
private struct TaskMark: View {
    var isEnabled: Bool
    var isRunning: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isEnabled ? AnyShapeStyle(.ember.opacity(0.14)) : AnyShapeStyle(.quaternary.opacity(0.6)))
            if isRunning {
                FlameGlyph(heat: .warming, height: 16)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            } else {
                Image(systemName: isEnabled ? "clock.fill" : "pause.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isEnabled ? AnyShapeStyle(.ember) : AnyShapeStyle(.secondary))
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: 26, height: 26)
        .animation(.spring(duration: 0.4, bounce: 0.3), value: isRunning)
        .accessibilityHidden(true)
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

import CoolifyAPI
import SwiftUI

/// Adds a scheduled task, or changes one. Frequency is a preset name or any string Coolify accepts.
struct TaskEditor: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss

    /// `nil` to add a task.
    var task: ScheduledTask?
    var onSave: (ScheduledTaskDraft) async throws -> Void

    @State private var name: String
    @State private var command: String
    @State private var preset: TaskFrequency
    @State private var customFrequency: String
    @State private var containerName: String
    @State private var timeout: Int
    @State private var enabled: Bool
    @State private var isSaving = false
    @State private var saveError: String?
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case name
        case command
        case frequency
        case container
    }

    init(task: ScheduledTask?, onSave: @escaping (ScheduledTaskDraft) async throws -> Void) {
        self.task = task
        self.onSave = onSave
        let preset = TaskFrequency.match(task?.frequency ?? "daily")
        _name = State(initialValue: task?.name ?? "")
        _command = State(initialValue: task?.command ?? "")
        _preset = State(initialValue: preset)
        _customFrequency = State(initialValue: preset == .custom ? (task?.frequency ?? "") : "")
        _containerName = State(initialValue: task?.container ?? "")
        _timeout = State(initialValue: task?.timeout ?? 300)
        _enabled = State(initialValue: task?.enabled ?? true)
    }

    private var isNew: Bool { task == nil }

    /// A preset the task already used stays as Coolify stored it, cron or name. A new choice sends the preset's name.
    private var frequency: String {
        if let task, preset == TaskFrequency.match(task.frequency), preset != .custom {
            return task.frequency
        }
        if let named = preset.named {
            return named
        }
        return customFrequency.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedCommand: String {
        command.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !trimmedCommand.isEmpty && !frequency.isEmpty && timeout >= 1 && !isSaving
    }

    private var hasEdits: Bool {
        guard let task else {
            return !name.isEmpty || !command.isEmpty || !containerName.isEmpty || preset != .daily || !enabled
                || timeout != 300
        }
        return trimmedName != task.name || trimmedCommand != task.command || frequency != task.frequency
            || containerName.trimmingCharacters(in: .whitespacesAndNewlines) != (task.container ?? "")
            || timeout != task.timeout || enabled != task.enabled
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Clear cache"))
                        .focused($focus, equals: .name)
                        .onSubmit { focus = .command }
                    TextField("Command", text: $command, prompt: Text("php artisan cache:clear"), axis: .vertical)
                        .font(.body.monospaced())
                        .lineLimit(1...6)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .command)
                }

                Section {
                    Picker("Frequency", selection: $preset) {
                        ForEach(TaskFrequency.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    if preset == .custom {
                        TextField("Frequency", text: $customFrequency, prompt: Text("0 0 * * *"))
                            .font(.body.monospaced())
                            .autocorrectionDisabled()
                            .focused($focus, equals: .frequency)
                    }
                } footer: {
                    Text("Hourly, daily, weekly, and monthly are names Coolify knows. Custom is any cron expression.")
                }

                Section {
                    TextField("Container", text: $containerName, prompt: Text("Optional"))
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        .focused($focus, equals: .container)
                    TextField("Timeout", value: $timeout, format: .number.grouping(.never))
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    Toggle("Enabled", isOn: $enabled)
                } footer: {
                    Text("Timeout is in seconds. Coolify uses 300 when a new task leaves it out. At least one second.")
                }

                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.glow)
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "New Task" : "Edit Task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button(isNew ? "Add" : "Save") {
                            Task { await save() }
                        }
                        .disabled(!canSave)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .onAppear { focus = isNew ? .name : .command }
            .onChange(of: name) { _, _ in saveError = nil }
            .onChange(of: command) { _, _ in saveError = nil }
            .onChange(of: customFrequency) { _, _ in saveError = nil }
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 500, minHeight: 460)
        #endif
        .interactiveDismissDisabled(isSaving || hasEdits)
        .animation(.snappy, value: saveError)
        .animation(.snappy, value: preset)
    }

    /// Blank stays out of a create. On a task that already names a container, blank sends `""` so Coolify clears it.
    /// A nil container would omit the key, and the update would leave the old container in place.
    private var containerToSend: String? {
        let trimmed = containerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        let existing = task?.container?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return existing.isEmpty ? nil : ""
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let draft = ScheduledTaskDraft(
            name: trimmedName,
            command: trimmedCommand,
            frequency: frequency,
            container: containerToSend,
            timeout: timeout,
            enabled: enabled
        )
        do {
            try await onSave(draft)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

#Preview("New") {
    TaskEditor(task: nil, onSave: { _ in })
}

#Preview("Edit") {
    TaskEditor(
        task: ScheduledTask(
            uuid: "task-1",
            enabled: true,
            name: "Clear cache",
            command: "php artisan cache:clear",
            frequency: "0 0 * * *",
            container: "worker",
            timeout: 120
        ),
        onSave: { _ in }
    )
}

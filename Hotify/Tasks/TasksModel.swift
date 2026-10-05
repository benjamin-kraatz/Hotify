import CoolifyAPI
import Foundation

/// Loads and changes the scheduled tasks of one application or service.
@Observable
final class TasksModel {
    var tasks: [ScheduledTask] = []
    var executions: [ScheduledTaskExecution] = []
    var loadError: String?
    var writeError: String?
    var executionError: String?
    var isLoading = false
    var isLoadingExecutions = false
    /// Whether a load has finished, so an empty list means no tasks rather than not yet.
    var hasLoaded = false
    /// The task whose Run Now is in flight. A lost response is not sent again.
    private(set) var runningUUID: String?

    private var client: CoolifyClient?
    private var owner: ScheduledTaskOwner?
    private var generation = 0
    private var executionTask: String?

    /// Clears the previous resource and points later loads and writes at this one.
    func prepare(_ client: CoolifyClient, owner: ScheduledTaskOwner) {
        generation += 1
        self.client = client
        self.owner = owner
        tasks = []
        executions = []
        executionTask = nil
        hasLoaded = false
        loadError = nil
        writeError = nil
        executionError = nil
        runningUUID = nil
    }

    func isRunning(_ task: ScheduledTask) -> Bool {
        runningUUID == task.uuid
    }

    func refresh() async {
        guard let client, let owner else { return }
        let generation = self.generation
        if !hasLoaded {
            isLoading = true
        }
        defer {
            if generation == self.generation {
                isLoading = false
            }
        }
        do {
            let loaded = try await client.scheduledTasks(for: owner)
            guard generation == self.generation else { return }
            tasks = loaded
            hasLoaded = true
            loadError = nil
            if let executionTask {
                await loadExecutions(executionTask)
            }
        } catch is CancellationError {
            return
        } catch {
            guard generation == self.generation else { return }
            loadError = Self.message(for: error)
        }
    }

    /// Drops the open history so a poll does not keep reading a task the user closed.
    func stopWatchingExecutions() {
        executionTask = nil
        executions = []
        executionError = nil
        isLoadingExecutions = false
    }

    func loadExecutions(_ taskUUID: String) async {
        guard let client, let owner else { return }
        let generation = self.generation
        let switching = executionTask != taskUUID
        if switching {
            executions = []
            executionError = nil
        }
        let sameTask = !switching && !executions.isEmpty
        executionTask = taskUUID
        if !sameTask {
            isLoadingExecutions = true
        }
        defer {
            if generation == self.generation, executionTask == taskUUID {
                isLoadingExecutions = false
            }
        }
        do {
            let loaded = try await client.scheduledTaskExecutions(taskUUID, for: owner)
            guard generation == self.generation, executionTask == taskUUID else { return }
            executions = Self.newestFirst(loaded)
            executionError = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == self.generation, executionTask == taskUUID else { return }
            executionError = Self.message(for: error)
        }
    }

    /// Creates or updates a task, then reloads. Throws a message the editor can show.
    func save(_ draft: ScheduledTaskDraft, updating taskUUID: String?) async throws {
        guard let client, let owner else { return }
        do {
            if let taskUUID {
                _ = try await client.updateScheduledTask(taskUUID, draft, on: owner)
            } else {
                _ = try await client.createScheduledTask(draft, on: owner)
            }
        } catch {
            throw TaskWriteError(message: Self.message(for: error))
        }
        writeError = nil
        await refresh()
    }

    func delete(_ task: ScheduledTask) async {
        guard let client, let owner else { return }
        do {
            try await client.deleteScheduledTask(task.uuid, from: owner)
            if executionTask == task.uuid {
                executionTask = nil
                executions = []
            }
            writeError = nil
            await refresh()
        } catch {
            writeError = Self.message(for: error)
        }
    }

    /// Asks Coolify to run the task once. Does not retry if the response never arrives.
    func run(_ task: ScheduledTask) async {
        guard let client, let owner, runningUUID != task.uuid else { return }
        runningUUID = task.uuid
        defer {
            if runningUUID == task.uuid {
                runningUUID = nil
            }
        }
        do {
            try await client.executeScheduledTask(task.uuid, on: owner)
            writeError = nil
            await loadExecutions(task.uuid)
        } catch is CancellationError {
            return
        } catch {
            writeError = "The run could not be confirmed. Check the history before trying again."
        }
    }

    private static func newestFirst(_ executions: [ScheduledTaskExecution]) -> [ScheduledTaskExecution] {
        executions.sorted { lhs, rhs in
            let left = lhs.startedAtDate ?? lhs.createdAtDate ?? .distantPast
            let right = rhs.startedAtDate ?? rhs.createdAtDate ?? .distantPast
            return left > right
        }
    }

    private static func message(for error: Error) -> String {
        (error as? CoolifyError)?.summary ?? error.localizedDescription
    }
}

private struct TaskWriteError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

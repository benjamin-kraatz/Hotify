import Foundation

/// The application or service whose scheduled tasks a request reads or changes.
public enum ScheduledTaskOwner: Sendable, Hashable {
    case application(String)
    case service(String)

    var path: String {
        switch self {
        case .application(let uuid):
            "applications/\(CoolifyURL.encodePathComponent(uuid))/scheduled-tasks"
        case .service(let uuid):
            "services/\(CoolifyURL.encodePathComponent(uuid))/scheduled-tasks"
        }
    }

    func taskPath(_ taskUUID: String) -> String {
        "\(path)/\(CoolifyURL.encodePathComponent(taskUUID))"
    }
}

extension CoolifyClient {
    /// Lists the owner's scheduled tasks.
    public func scheduledTasks(for owner: ScheduledTaskOwner) async throws -> [ScheduledTask] {
        try await getList(owner.path)
    }

    /// Adds a task. Coolify answers 422 when the frequency is not a cron expression or one of its names.
    public func createScheduledTask(
        _ draft: ScheduledTaskDraft,
        on owner: ScheduledTaskOwner
    ) async throws -> ScheduledTask {
        try await post(owner.path, body: draft)
    }

    /// Replaces the fields the draft includes. Keys left nil stay as Coolify has them.
    public func updateScheduledTask(
        _ taskUUID: String,
        _ draft: ScheduledTaskDraft,
        on owner: ScheduledTaskOwner
    ) async throws -> ScheduledTask {
        try await patch(owner.taskPath(taskUUID), body: draft)
    }

    public func deleteScheduledTask(_ taskUUID: String, from owner: ScheduledTaskOwner) async throws {
        let _: QueuedAction = try await delete(owner.taskPath(taskUUID))
    }

    /// Queues the task to run once, now. Coolify answers before the command finishes.
    public func executeScheduledTask(_ taskUUID: String, on owner: ScheduledTaskOwner) async throws {
        let _: QueuedAction = try await post("\(owner.taskPath(taskUUID))/execute")
    }

    /// Lists the runs of one task, oldest or newest as Coolify returns them.
    public func scheduledTaskExecutions(
        _ taskUUID: String,
        for owner: ScheduledTaskOwner
    ) async throws -> [ScheduledTaskExecution] {
        try await getList("\(owner.taskPath(taskUUID))/executions")
    }
}

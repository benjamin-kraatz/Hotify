import CoolifyAPI
import Foundation

/// Every restore Hotify started while it runs, one per database. Closing the sheet or leaving the tab neither stops
/// nor forgets one.
///
/// A restore uploads a file from this device when there is one, asks Coolify to start the import, then reads its
/// status every few seconds until Coolify reports an end. Only the upload can be cancelled, because Coolify has no way
/// to stop an import once it is queued.
@Observable
@MainActor
final class DatabaseRestores {
    /// Status reads that fail in a row before Hotify stops following and says so.
    static let lostTrackAfter = 4

    private(set) var jobs: [DatabaseImportTarget: RestoreJob] = [:]
    private var tasks: [DatabaseImportTarget: Task<Void, Never>] = [:]
    private var clients: [DatabaseImportTarget: CoolifyClient] = [:]
    private let pollInterval: Duration

    init(pollInterval: Duration = .seconds(3), jobs: [RestoreJob] = []) {
        self.pollInterval = pollInterval
        for job in jobs {
            self.jobs[job.target.importTarget] = job
        }
    }

    func job(for target: DatabaseImportTarget) -> RestoreJob? {
        jobs[target]
    }

    func isActive(_ target: DatabaseImportTarget) -> Bool {
        jobs[target]?.stage.isActive == true
    }

    /// Starts a restore, replacing a finished one for the same database. Does nothing while one is still active.
    func start(_ request: RestoreRequest, client: CoolifyClient) {
        let target = request.target.importTarget
        guard !isActive(target) else { return }
        var job = RestoreJob(target: request.target, sourceLabel: request.sourceLabel, stage: .starting)
        if case .file(let file) = request.origin {
            job.stage = .uploading
            job.totalBytes = file.size
        }
        jobs[target] = job
        clients[target] = client
        tasks[target] = Task { [weak self] in
            await self?.run(request, client: client, jobID: job.id)
        }
    }

    /// Stops an upload. Coolify cleans up the chunks it already has on its own.
    func cancelUpload(_ target: DatabaseImportTarget) {
        guard jobs[target]?.stage == .uploading else { return }
        tasks[target]?.cancel()
    }

    /// Forgets a restore that ended.
    func dismiss(_ target: DatabaseImportTarget) {
        guard !isActive(target) else { return }
        jobs[target] = nil
        tasks[target] = nil
        clients[target] = nil
    }

    /// Follows an import again after Hotify lost track of it.
    func checkAgain(_ target: DatabaseImportTarget) {
        guard let job = jobs[target], job.stage == .lostTrack, let activity = job.activityID,
            let client = clients[target]
        else { return }
        update(target, jobID: job.id) {
            $0.stage = .restoring
            $0.problem = nil
            $0.finishedAt = nil
        }
        tasks[target] = Task { [weak self] in
            await self?.follow(target, activity: activity, client: client, jobID: job.id)
        }
    }

    private func run(_ request: RestoreRequest, client: CoolifyClient, jobID: UUID) async {
        let target = request.target.importTarget
        let source: DatabaseImportSource
        switch request.origin {
        case .file(let file):
            guard let uploadID = await upload(file, to: target, client: client, jobID: jobID) else { return }
            source = .upload(uploadID)
        case .stored(let stored):
            source = stored
        }

        update(target, jobID: jobID) { $0.stage = .starting }
        let queued: QueuedDatabaseImport
        do {
            queued = try await client.startDatabaseImport(target, source: source, options: request.options)
        } catch {
            fail(target, jobID: jobID, problem: RestoreProblem.message(for: error, source: source))
            return
        }
        update(target, jobID: jobID) {
            $0.activityID = queued.id
            $0.coolifyStatus = queued.phase.rawValue
            $0.stage = queued.phase == .queued ? .queued : .restoring
        }
        await follow(target, activity: queued.id, client: client, jobID: jobID)
    }

    /// Returns the upload id, or `nil` after the upload failed or was cancelled.
    private func upload(
        _ file: RestoreFile,
        to target: DatabaseImportTarget,
        client: CoolifyClient,
        jobID: UUID
    ) async -> String? {
        // The picker's access to the file lasts for the whole upload, and ends with it.
        let access = file.url.startAccessingSecurityScopedResource()
        defer { if access { file.url.stopAccessingSecurityScopedResource() } }
        let assertion = UploadAssertion()
        assertion.begin()
        defer { assertion.end() }
        do {
            // The store lives as long as the app, so the progress callback can hold it.
            let upload = try await client.uploadDatabaseImport(target, file: file.url, filename: file.name) {
                progress in
                Task { @MainActor in self.record(progress, for: target, jobID: jobID) }
            }
            // A cancel that arrived with the last chunk still means the user does not want this import.
            if Task.isCancelled {
                update(target, jobID: jobID) { $0.stage = .uploadCancelled }
                finish(target, jobID: jobID)
                return nil
            }
            return upload.uploadID
        } catch {
            if error is CancellationError || Task.isCancelled {
                update(target, jobID: jobID) { $0.stage = .uploadCancelled }
                finish(target, jobID: jobID)
            } else {
                fail(target, jobID: jobID, problem: RestoreProblem.message(for: error, source: nil))
            }
            return nil
        }
    }

    private func follow(_ target: DatabaseImportTarget, activity: Int, client: CoolifyClient, jobID: UUID) async {
        var failures = 0
        while !Task.isCancelled {
            do { try await Task.sleep(for: pollInterval) } catch { return }
            do {
                let status = try await client.databaseImport(target, activity: activity)
                failures = 0
                update(target, jobID: jobID) {
                    $0.coolifyStatus = status.phase.rawValue
                    $0.exitCode = status.exitCode
                    if let output = status.output { $0.output = output }
                    if status.isTerminal {
                        $0.stage = status.succeeded ? .succeeded : .failed
                    } else {
                        $0.stage = status.phase == .queued ? .queued : .restoring
                    }
                }
                if status.isTerminal {
                    finish(target, jobID: jobID)
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                failures += 1
                guard failures >= Self.lostTrackAfter else { continue }
                let reason = (error as? CoolifyError)?.summary ?? error.localizedDescription
                update(target, jobID: jobID) {
                    $0.stage = .lostTrack
                    $0.problem =
                        "Hotify could not read the import's status (\(reason)). The import may still be running in "
                        + "Coolify, so check the database before you start another."
                }
                finish(target, jobID: jobID)
                return
            }
        }
    }

    private func record(_ progress: DatabaseImportProgress, for target: DatabaseImportTarget, jobID: UUID) {
        // Progress hops here in its own task, so a late one must not move the bar back or revive a finished upload.
        guard let job = jobs[target], job.id == jobID, job.stage == .uploading,
            progress.sentBytes >= job.sentBytes
        else { return }
        update(target, jobID: jobID) {
            $0.sentBytes = progress.sentBytes
            $0.totalBytes = progress.totalBytes
        }
    }

    private func fail(_ target: DatabaseImportTarget, jobID: UUID, problem: String) {
        update(target, jobID: jobID) {
            $0.stage = .failed
            $0.problem = problem
        }
        finish(target, jobID: jobID)
    }

    private func finish(_ target: DatabaseImportTarget, jobID: UUID) {
        update(target, jobID: jobID) { $0.finishedAt = .now }
        tasks[target] = nil
    }

    /// Changes the job only while it is still the one this task runs, never a newer restore of the same database.
    private func update(_ target: DatabaseImportTarget, jobID: UUID, _ change: (inout RestoreJob) -> Void) {
        guard var job = jobs[target], job.id == jobID else { return }
        change(&job)
        jobs[target] = job
    }
}

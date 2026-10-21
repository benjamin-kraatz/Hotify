import CoolifyAPI
import Foundation

/// The selected instance's team alert channels, as Coolify last returned them. Nothing here is stored.
@MainActor
@Observable
final class CoolifyAlertsModel {
    /// The instance the channels belong to. A save goes to this one even if the selection moves on.
    private(set) var instanceID: UUID?
    var channels: [NotificationChannel: NotificationChannelSettings] = [:]
    var failures: [NotificationChannel: String] = [:]
    var teamName: String?
    /// Why no channel could be read, such as an older Coolify or a token without access.
    var unavailable: String?
    var notice: String?
    var isLoading = false
    var hasLoaded = false

    init() {}

    /// Shows fixed channels without touching the network, as a preview does.
    init(
        preview channels: [NotificationChannelSettings],
        instanceID: UUID,
        teamName: String?,
        failures: [NotificationChannel: String] = [:]
    ) {
        self.instanceID = instanceID
        for settings in channels {
            self.channels[settings.channel] = settings
        }
        self.failures = failures
        self.teamName = teamName
        hasLoaded = true
    }

    func load(_ client: CoolifyClient, instanceID: UUID) async {
        if self.instanceID != instanceID {
            self.instanceID = instanceID
            channels = [:]
            failures = [:]
            teamName = nil
            notice = nil
            hasLoaded = false
        }
        unavailable = nil
        isLoading = true
        defer { isLoading = false }

        async let team = try? client.currentTeam()
        let results = await withTaskGroup(
            of: (NotificationChannel, Result<NotificationChannelSettings, any Error>).self
        ) { group in
            for channel in NotificationChannel.allCases {
                group.addTask {
                    do {
                        return (channel, .success(try await client.notificationSettings(channel)))
                    } catch {
                        return (channel, .failure(error))
                    }
                }
            }
            var results: [NotificationChannel: Result<NotificationChannelSettings, any Error>] = [:]
            for await (channel, result) in group {
                results[channel] = result
            }
            return results
        }
        let teamName = await team?.name
        guard !Task.isCancelled, self.instanceID == instanceID else { return }

        self.teamName = teamName
        var loaded: [NotificationChannel: NotificationChannelSettings] = [:]
        var failed: [NotificationChannel: any Error] = [:]
        for (channel, result) in results {
            switch result {
            case .success(let settings): loaded[channel] = settings
            case .failure(let error): failed[channel] = error
            }
        }
        if loaded.isEmpty, let error = failed[.email] ?? failed.values.first {
            if error is CancellationError { return }
            unavailable = AlertFailure.loading(error)
        }
        channels = loaded
        failures = failed.filter { !($0.value is CancellationError) }.mapValues(AlertFailure.loading)
        hasLoaded = true
    }

    /// Takes the settings Coolify answered a save with, if they belong to the instance shown.
    func apply(_ saved: NotificationChannelSettings, instanceID: UUID) {
        guard self.instanceID == instanceID else { return }
        channels[saved.channel] = saved
        failures[saved.channel] = nil
        notice = "\(saved.channel.title) saved in Coolify."
    }
}

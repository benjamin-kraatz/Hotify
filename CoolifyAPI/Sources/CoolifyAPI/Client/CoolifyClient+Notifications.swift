import Foundation

extension CoolifyClient {
    /// Reads the token's team settings for one alert channel.
    ///
    /// Coolify creates the record on first read. Hidden fields, such as webhook addresses and passwords, are only in
    /// the response when the token has `read:sensitive` and its user is a team admin or owner. A 404 means the
    /// instance's Coolify version has no such endpoint.
    public func notificationSettings(_ channel: NotificationChannel) async throws -> NotificationChannelSettings {
        try await withoutBody {
            let (data, response) = try await send("GET", path: channel.path)
            return try decodeNotificationSettings(channel, data: data, response: response)
        }
    }

    /// Sends only the keys in `update` and returns the settings Coolify saved.
    ///
    /// Changing settings needs the `write` ability and a team admin or owner, or Coolify answers 403. An empty update
    /// throws without a request, since Coolify answers 400 to an empty body.
    public func updateNotificationSettings(_ update: NotificationChannelUpdate) async throws
        -> NotificationChannelSettings
    {
        guard !update.isEmpty else {
            throw CoolifyError(message: "There are no changes to save.")
        }
        return try await withoutBody {
            let body = try CoolifyJSON.encoder().encode(update)
            let (data, response) = try await send("PATCH", path: update.channel.path, body: body)
            return try decodeNotificationSettings(update.channel, data: data, response: response)
        }
    }

    private func decodeNotificationSettings(
        _ channel: NotificationChannel,
        data: Data,
        response: HTTPURLResponse
    ) throws -> NotificationChannelSettings {
        do {
            return try NotificationChannelSettings.decode(channel, from: data)
        } catch {
            throw CoolifyError(
                statusCode: response.statusCode,
                message: "Coolify answered with settings Hotify could not read."
            )
        }
    }

    /// Strips the response body from any error, since a body here can hold webhook addresses and credentials.
    ///
    /// A message Coolify did not send as JSON is the raw body, such as a debug page that echoes the request, so it is
    /// replaced too.
    private func withoutBody<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch var error as CoolifyError {
            if let body = error.responseBody, error.message == body {
                error.message = error.statusCode.map { "Coolify returned HTTP \($0)." } ?? "Coolify did not answer."
            }
            error.responseBody = nil
            throw error
        }
    }
}

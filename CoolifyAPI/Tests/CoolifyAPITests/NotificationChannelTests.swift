import Foundation
import XCTest

@testable import CoolifyAPI

final class NotificationChannelTests: XCTestCase {
    override func tearDown() {
        NotificationChannelURLProtocol.responder = nil
        super.tearDown()
    }

    // MARK: Reading

    func testReadsEveryChannelFromItsOwnPath() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(queryItems(request).isEmpty)
            XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
            let channel = request.url?.lastPathComponent ?? ""
            return (200, Data(#"{"id":1,"team_id":7,"\#(channel)_enabled":false}"#.utf8), [:])
        }
        for channel in NotificationChannel.allCases where channel != .email {
            let settings = try await client.notificationSettings(channel)
            XCTAssertEqual(settings.channel, channel)
            XCTAssertEqual(settings.bool("\(channel.rawValue)_enabled"), false)
        }
        let paths = NotificationChannel.allCases.map(\.path)
        XCTAssertEqual(
            paths,
            [
                "notifications/email", "notifications/discord", "notifications/slack", "notifications/telegram",
                "notifications/pushover", "notifications/webhook",
            ])
    }

    /// A read-only token: Coolify leaves the webhook address out and sends flags as 0, 1, and strings.
    func testDiscordWithoutSensitiveValuesWithholdsTheWebhook() throws {
        let fixture = """
            {"id":3,"team_id":1,"discord_enabled":1,"discord_ping_enabled":"0",\
            "deployment_success_discord_notifications":false,"deployment_failure_discord_notifications":"1",\
            "status_change_discord_notifications":0,"restart_limit_reached_discord_notifications":true,\
            "backup_success_discord_notifications":false,"backup_failure_discord_notifications":true,\
            "scheduled_task_success_discord_notifications":false,"scheduled_task_failure_discord_notifications":true,\
            "docker_cleanup_success_discord_notifications":false,"docker_cleanup_failure_discord_notifications":true,\
            "server_disk_usage_discord_notifications":true,"server_reachable_discord_notifications":false,\
            "server_unreachable_discord_notifications":true,"server_patch_discord_notifications":false,\
            "traefik_outdated_discord_notifications":true}
            """
        let settings = try NotificationChannelSettings.decode(.discord, from: Data(fixture.utf8))
        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.bool("discord_ping_enabled"), false)
        XCTAssertEqual(settings.offeredEvents, NotificationChannelEvent.allCases)
        XCTAssertEqual(settings.isSubscribed(.deploymentFailure), true)
        XCTAssertEqual(settings.isSubscribed(.statusChange), false)
        XCTAssertFalse(settings.revealsSensitiveValues)
        let webhook = try XCTUnwrap(NotificationChannel.discord.field("discord_webhook_url"))
        XCTAssertTrue(settings.isWithheld(webhook))
        XCTAssertTrue(settings.offers(webhook))
        XCTAssertNil(settings.value("id"))
        XCTAssertNil(settings.value("team_id"))
    }

    /// A `read:sensitive` token from an admin: hidden fields arrive, and the port may come as a string.
    func testEmailWithSensitiveValues() throws {
        let fixture = """
            {"id":1,"team_id":1,"smtp_enabled":true,"resend_enabled":false,"use_instance_email_settings":0,\
            "smtp_from_address":"alerts@example.com","smtp_from_name":"Coolify","smtp_recipients":null,\
            "smtp_host":"smtp.example.com","smtp_port":"587","smtp_encryption":"starttls",\
            "smtp_username":"mailer","smtp_password":"mail-secret","smtp_timeout":30,"smtp_ehlo_domain":null,\
            "resend_api_key":null,"deployment_failure_email_notifications":true,"unknown_future_field":"x"}
            """
        let settings = try NotificationChannelSettings.decode(.email, from: Data(fixture.utf8))
        XCTAssertTrue(settings.isEnabled)
        XCTAssertTrue(settings.revealsSensitiveValues)
        XCTAssertEqual(settings.value("smtp_port"), .integer(587))
        XCTAssertEqual(settings.text("smtp_port"), "587")
        XCTAssertEqual(settings.value("smtp_recipients"), .null)
        XCTAssertEqual(settings.value("smtp_ehlo_domain"), .null)
        XCTAssertEqual(settings.text("smtp_password"), "mail-secret")
        XCTAssertEqual(settings.bool("use_instance_email_settings"), false)
        XCTAssertNil(settings.value("unknown_future_field"))
        let password = try XCTUnwrap(NotificationChannel.email.field("smtp_password"))
        XCTAssertFalse(settings.isWithheld(password))
        XCTAssertEqual(settings.offeredEvents, [.deploymentFailure])
    }

    /// An older Coolify without the EHLO domain or the Traefik event: neither is offered.
    func testMissingVisibleFieldsAreNotOffered() throws {
        let fixture = #"{"smtp_enabled":false,"smtp_port":null,"deployment_success_email_notifications":true}"#
        let settings = try NotificationChannelSettings.decode(.email, from: Data(fixture.utf8))
        let ehlo = try XCTUnwrap(NotificationChannel.email.field("smtp_ehlo_domain"))
        let host = try XCTUnwrap(NotificationChannel.email.field("smtp_host"))
        XCTAssertFalse(settings.offers(ehlo))
        XCTAssertTrue(settings.offers(host))
        XCTAssertFalse(settings.isEnabled)
        XCTAssertEqual(settings.offeredEvents, [.deploymentSuccess])
        XCTAssertNil(settings.isSubscribed(.traefikOutdated))
    }

    func testTelegramThreadsAreHiddenAndOnlyTelegramHasThem() throws {
        let key = try XCTUnwrap(NotificationChannel.telegram.threadKey(.backupFailure))
        XCTAssertEqual(key, "telegram_notifications_backup_failure_thread_id")
        XCTAssertEqual(NotificationChannel.telegram.field(key)?.isHidden, true)
        XCTAssertNil(NotificationChannel.slack.threadKey(.backupFailure))
        let fixture = #"{"telegram_enabled":true,"telegram_chat_id":"-100123","\#(key)":"42"}"#
        let settings = try NotificationChannelSettings.decode(.telegram, from: Data(fixture.utf8))
        XCTAssertEqual(settings.text(key), "42")
        XCTAssertEqual(settings.text("telegram_chat_id"), "-100123")
    }

    // MARK: Writing

    func testUpdateSendsOnlyChangedKeysAndReturnsSavedSettings() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/notifications/slack")
            XCTAssertTrue(queryItems(request).isEmpty)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(
                bodyText(request),
                #"{"backup_failure_slack_notifications":true,"slack_enabled":true}"#
            )
            return (
                200,
                Data(#"{"team_id":1,"slack_enabled":true,"backup_failure_slack_notifications":true}"#.utf8),
                [:]
            )
        }
        var update = NotificationChannelUpdate(channel: .slack)
        update.set(.bool(true), for: "slack_enabled")
        update.subscribe(.backupFailure, true)
        let saved = try await client.updateNotificationSettings(update)
        XCTAssertTrue(saved.isEnabled)
        XCTAssertEqual(saved.isSubscribed(.backupFailure), true)
    }

    func testBlankCredentialsAndForeignKeysStayOutOfTheBody() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/notifications/pushover")
            XCTAssertEqual(bodyText(request), #"{"pushover_api_token":"new-token","pushover_enabled":true}"#)
            return (200, Data(#"{"pushover_enabled":true}"#.utf8), [:])
        }
        var update = NotificationChannelUpdate(channel: .pushover)
        update.set(.bool(true), for: "pushover_enabled")
        update.set(.text("   "), for: "pushover_user_key")
        update.setCredential("  new-token \n", for: "pushover_api_token")
        update.set(.bool(true), for: "team_id")
        update.set(.bool(true), for: "slack_enabled")
        _ = try await client.updateNotificationSettings(update)
    }

    func testClearSendsNullForTheSetting() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/notifications/email")
            // `webhook_url` belongs to another channel, so it stays out.
            XCTAssertEqual(bodyText(request), #"{"smtp_ehlo_domain":null,"smtp_port":2525}"#)
            return (200, Data(#"{"smtp_ehlo_domain":null,"smtp_port":2525}"#.utf8), [:])
        }
        var update = NotificationChannelUpdate(channel: .email)
        update.clear("smtp_ehlo_domain")
        update.set(.integer(2525), for: "smtp_port")
        update.clear("webhook_url")
        let saved = try await client.updateNotificationSettings(update)
        XCTAssertEqual(saved.value("smtp_ehlo_domain"), .null)
        XCTAssertEqual(saved.value("smtp_port"), .integer(2525))
    }

    func testWebhookAndTelegramWriteShapes() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            let body = try JSONSerialization.jsonObject(with: Data((bodyText(request) ?? "").utf8)) as? NSDictionary
            switch request.url?.path {
            case "/api/v1/notifications/webhook":
                XCTAssertEqual(
                    body,
                    ["webhook_enabled": true, "webhook_url": "https://hooks.example.com/coolify"] as NSDictionary)
            case "/api/v1/notifications/telegram":
                XCTAssertEqual(
                    body,
                    [
                        "telegram_chat_id": "-100123", "telegram_notifications_deployment_failure_thread_id": "7",
                        "deployment_failure_telegram_notifications": false,
                    ] as NSDictionary)
            case "/api/v1/notifications/discord":
                XCTAssertEqual(body, ["discord_ping_enabled": false] as NSDictionary)
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "")")
            }
            return (200, Data("{}".utf8), [:])
        }
        var webhook = NotificationChannelUpdate(channel: .webhook)
        webhook.set(.bool(true), for: "webhook_enabled")
        webhook.set(.text("https://hooks.example.com/coolify"), for: "webhook_url")
        _ = try await client.updateNotificationSettings(webhook)

        var telegram = NotificationChannelUpdate(channel: .telegram)
        telegram.set(.text("-100123"), for: "telegram_chat_id")
        telegram.set(.text("7"), for: try XCTUnwrap(NotificationChannel.telegram.threadKey(.deploymentFailure)))
        telegram.subscribe(.deploymentFailure, false)
        _ = try await client.updateNotificationSettings(telegram)

        var discord = NotificationChannelUpdate(channel: .discord)
        discord.set(.bool(false), for: "discord_ping_enabled")
        _ = try await client.updateNotificationSettings(discord)
    }

    func testEmptyUpdateThrowsWithoutARequest() async throws {
        let client = try makeClient { _ in
            XCTFail("An empty update must not reach Coolify.")
            return (400, Data(#"{"message":"Invalid request.","error":"Empty JSON."}"#.utf8), [:])
        }
        var update = NotificationChannelUpdate(channel: .discord)
        update.setCredential("", for: "discord_webhook_url")
        XCTAssertTrue(update.isEmpty)
        do {
            _ = try await client.updateNotificationSettings(update)
            XCTFail("Expected an error.")
        } catch let error as CoolifyError {
            XCTAssertNil(error.statusCode)
        }
    }

    // MARK: Errors

    func testValidationErrorKeepsFieldsAndDropsTheBody() async throws {
        let client = try makeClient { _ in
            let body = """
                {"message":"Validation failed.","errors":{"discord_webhook_url":\
                ["The discord webhook url must not point to private networks."]}}
                """
            return (422, Data(body.utf8), [:])
        }
        var update = NotificationChannelUpdate(channel: .discord)
        update.set(.text("https://10.0.0.5/hook/secret-part"), for: "discord_webhook_url")
        do {
            _ = try await client.updateNotificationSettings(update)
            XCTFail("Expected an error.")
        } catch let error as CoolifyError {
            XCTAssertTrue(error.isValidation)
            XCTAssertEqual(error.message, "Validation failed.")
            XCTAssertEqual(error.fieldErrors["discord_webhook_url"]?.count, 1)
            XCTAssertNil(error.responseBody)
        }
    }

    func testRawErrorPageNeverReachesTheMessage() async throws {
        let client = try makeClient { _ in
            (500, Data("<html>request: {\"webhook_url\":\"https://hooks.example.com/secret-token\"}</html>".utf8), [:])
        }
        var update = NotificationChannelUpdate(channel: .webhook)
        update.set(.text("https://hooks.example.com/secret-token"), for: "webhook_url")
        do {
            _ = try await client.updateNotificationSettings(update)
            XCTFail("Expected an error.")
        } catch let error as CoolifyError {
            XCTAssertEqual(error.statusCode, 500)
            XCTAssertEqual(error.message, "Coolify returned HTTP 500.")
            XCTAssertNil(error.responseBody)
            XCTAssertFalse(error.summary.contains("secret-token"))
        }
    }

    func testUnreadableSettingsDoNotEchoTheBody() async throws {
        let client = try makeClient { _ in
            (200, Data(#"["https://discord.com/api/webhooks/1/secret-token"]"#.utf8), [:])
        }
        do {
            _ = try await client.notificationSettings(.discord)
            XCTFail("Expected an error.")
        } catch let error as CoolifyError {
            XCTAssertEqual(error.statusCode, 200)
            XCTAssertNil(error.responseBody)
            XCTAssertFalse(error.message.contains("secret-token"))
        }
    }

    func testPermissionAndMissingEndpointErrors() async throws {
        let forbidden = try makeClient { _ in
            (403, Data(#"{"message":"Missing required permissions: write"}"#.utf8), [:])
        }
        var update = NotificationChannelUpdate(channel: .slack)
        update.set(.bool(true), for: "slack_enabled")
        do {
            _ = try await forbidden.updateNotificationSettings(update)
            XCTFail("Expected an error.")
        } catch let error as CoolifyError {
            XCTAssertTrue(error.isForbidden)
            XCTAssertEqual(error.message, "Missing required permissions: write")
        }

        let missing = try makeClient { _ in
            (404, Data(#"{"message":"Not found."}"#.utf8), [:])
        }
        do {
            _ = try await missing.notificationSettings(.slack)
            XCTFail("Expected an error.")
        } catch let error as CoolifyError {
            XCTAssertTrue(error.isNotFound)
        }
    }

    // MARK: Secrets and validation

    func testDescriptionsNameKeysButNeverValues() throws {
        let settings = NotificationChannelSettings(
            channel: .webhook,
            values: ["webhook_enabled": .bool(true), "webhook_url": .text("https://hooks.example.com/secret-token")]
        )
        var update = NotificationChannelUpdate(channel: .webhook)
        update.set(.text("https://hooks.example.com/other-secret"), for: "webhook_url")
        for text in [
            String(describing: settings), String(reflecting: settings), String(describing: update),
            String(reflecting: update), dumped(settings), dumped(update),
        ] {
            XCTAssertFalse(text.contains("secret"), text)
        }
        XCTAssertTrue(String(describing: settings).contains("webhook_url"))
    }

    func testFieldRulesFollowCoolify() throws {
        let email = NotificationChannel.email
        let address = try XCTUnwrap(email.field("smtp_from_address"))
        XCTAssertNil(address.problem(with: .text("alerts@example.com")))
        XCTAssertNotNil(address.problem(with: .text("alerts")))
        XCTAssertNil(address.problem(with: .null))

        let port = try XCTUnwrap(email.field("smtp_port"))
        XCTAssertNil(port.problem(with: .integer(587)))
        XCTAssertNotNil(port.problem(with: .integer(0)))
        XCTAssertNotNil(port.problem(with: .integer(70_000)))

        let timeout = try XCTUnwrap(email.field("smtp_timeout"))
        XCTAssertNil(timeout.problem(with: .integer(0)))
        XCTAssertNotNil(timeout.problem(with: .integer(-1)))

        let ehlo = try XCTUnwrap(email.field("smtp_ehlo_domain"))
        XCTAssertNil(ehlo.problem(with: .text("mail.example.com")))
        XCTAssertNotNil(ehlo.problem(with: .text("not a hostname")))
        XCTAssertNotNil(ehlo.problem(with: .text("-bad.example.com")))
        XCTAssertNotNil(ehlo.problem(with: .text("example..com")))

        let encryption = try XCTUnwrap(email.field("smtp_encryption"))
        XCTAssertNil(encryption.problem(with: .text("tls")))
        XCTAssertNotNil(encryption.problem(with: .text("ssl")))

        let recipients = try XCTUnwrap(email.field("smtp_recipients"))
        XCTAssertNil(recipients.problem(with: .text(String(repeating: "a", count: 1_000))))
        XCTAssertNotNil(recipients.problem(with: .text(String(repeating: "a", count: 1_001))))

        let webhook = try XCTUnwrap(NotificationChannel.slack.field("slack_webhook_url"))
        XCTAssertTrue(webhook.isCredential)
        XCTAssertNil(webhook.problem(with: .text("https://hooks.slack.com/services/T00/B00/xxx")))
        XCTAssertNotNil(webhook.problem(with: .text("ftp://hooks.example.com")))
        XCTAssertNotNil(webhook.problem(with: .text("https://")))

        var update = NotificationChannelUpdate(channel: .email)
        update.set(.text("nope"), for: "smtp_from_address")
        update.set(.integer(0), for: "smtp_port")
        XCTAssertEqual(Set(update.problems.keys), ["smtp_from_address", "smtp_port"])
    }

    func testTurningOnAChannelNeedsItsDestination() throws {
        let empty = NotificationChannelSettings(
            channel: .discord, values: ["discord_enabled": .bool(false), "discord_webhook_url": .null])
        var update = NotificationChannelUpdate(channel: .discord)
        update.set(.bool(true), for: "discord_enabled")
        XCTAssertEqual(update.missingKeys(applyingTo: empty), ["discord_webhook_url"])

        update.set(.text("https://discord.com/api/webhooks/1/abc"), for: "discord_webhook_url")
        XCTAssertEqual(update.missingKeys(applyingTo: empty), [])

        // A withheld address may be set, so only clearing it counts as missing.
        let withheld = NotificationChannelSettings(channel: .discord, values: ["discord_enabled": .bool(false)])
        var enable = NotificationChannelUpdate(channel: .discord)
        enable.set(.bool(true), for: "discord_enabled")
        XCTAssertEqual(enable.missingKeys(applyingTo: withheld), [])
        enable.clear("discord_webhook_url")
        XCTAssertEqual(enable.missingKeys(applyingTo: withheld), ["discord_webhook_url"])

        let mail = NotificationChannelSettings(
            channel: .email,
            values: [
                "smtp_enabled": .bool(true), "smtp_from_address": .text("alerts@example.com"),
                "smtp_from_name": .text("Coolify"), "smtp_host": .null, "smtp_port": .integer(587),
                "smtp_encryption": .text("tls"),
            ]
        )
        XCTAssertEqual(NotificationChannelUpdate(channel: .email).missingKeys(applyingTo: mail), ["smtp_host"])
        var instance = NotificationChannelUpdate(channel: .email)
        instance.set(.bool(false), for: "smtp_enabled")
        instance.set(.bool(true), for: "use_instance_email_settings")
        XCTAssertEqual(instance.missingKeys(applyingTo: mail), [])
    }

    func testEveryChannelKeyIsUnique() {
        for channel in NotificationChannel.allCases {
            let keys = channel.allFields.map(\.key)
            XCTAssertEqual(keys.count, Set(keys).count, channel.rawValue)
            XCTAssertFalse(keys.contains("team_id"))
            for key in channel.enableKeys {
                XCTAssertEqual(channel.field(key)?.kind, .toggle)
            }
        }
    }
}

private func dumped(_ value: some Any) -> String {
    var output = ""
    dump(value, to: &output)
    return output
}

private func bodyText(_ request: URLRequest) -> String? {
    if let body = request.httpBody {
        return String(decoding: body, as: UTF8.self)
    }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: buffer.count)
        guard read > 0 else { break }
        data.append(buffer, count: read)
    }
    return String(decoding: data, as: UTF8.self)
}

private func queryItems(_ request: URLRequest) -> [URLQueryItem] {
    guard let url = request.url else { return [] }
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
}

private func makeClient(
    responder: @escaping @Sendable (URLRequest) throws -> (Int, Data, [String: String])
) throws -> CoolifyClient {
    NotificationChannelURLProtocol.responder = responder
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [NotificationChannelURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return try CoolifyClient(instanceURL: "http://coolify.example:8000", token: "test-token", session: session)
}

/// Answers alert channel requests in tests. Not the suite's shared mock.
private final class NotificationChannelURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responder: (@Sendable (URLRequest) throws -> (Int, Data, [String: String]))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let responder = Self.responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (status, data, headers) = try responder(request)
            guard let url = request.url,
                let response = HTTPURLResponse(
                    url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

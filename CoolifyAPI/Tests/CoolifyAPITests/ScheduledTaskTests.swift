import Foundation
import XCTest

@testable import CoolifyAPI

final class ScheduledTaskTests: XCTestCase {
    func testCreateUpdateExecuteAndDeleteForApplicationAndService() async throws {
        let owners: [(ScheduledTaskOwner, String)] = [
            (.application("app-1"), "/api/v1/applications/app-1/scheduled-tasks"),
            (.service("svc-1"), "/api/v1/services/svc-1/scheduled-tasks"),
        ]
        let task = Data(
            #"{"uuid":"task-1","enabled":1,"name":"Nightly","command":"echo ok","frequency":"hourly","timeout":300}"#
                .utf8)
        let created = #"{"command":"echo ok","enabled":true,"frequency":"hourly","name":"Nightly","timeout":300}"#
        let updated =
            #"{"command":"echo ok","container":"worker","enabled":false,"frequency":"daily","#
            + #""name":"Nightly","timeout":120}"#

        for (owner, root) in owners {
            let client = try makeScheduledTaskClient { request in
                let method = request.httpMethod ?? ""
                let path = request.url?.path ?? ""
                switch (method, path) {
                case ("POST", root):
                    let body = scheduledTaskBody(request)
                    XCTAssertEqual(body, created)
                    XCTAssertFalse(body?.contains("\"container\"") ?? true)
                    return (201, task, [:])
                case ("PATCH", root + "/task-1"):
                    XCTAssertEqual(scheduledTaskBody(request), updated)
                    return (200, task, [:])
                case ("POST", root + "/task-1/execute"):
                    XCTAssertNil(scheduledTaskBody(request))
                    return (200, Data(#"{"message":"Scheduled task execution queued."}"#.utf8), [:])
                case ("DELETE", root + "/task-1"):
                    XCTAssertNil(scheduledTaskBody(request))
                    return (200, Data(#"{"message":"Scheduled task deleted."}"#.utf8), [:])
                default:
                    XCTFail("Unexpected \(method) \(path)")
                    return (500, Data(), [:])
                }
            }

            let made = try await client.createScheduledTask(
                ScheduledTaskDraft(
                    name: "Nightly", command: "echo ok", frequency: "hourly", timeout: 300, enabled: true),
                on: owner
            )
            XCTAssertEqual(made.enabled, true)
            XCTAssertNil(made.container)

            _ = try await client.updateScheduledTask(
                "task-1",
                ScheduledTaskDraft(
                    name: "Nightly",
                    command: "echo ok",
                    frequency: "daily",
                    container: "worker",
                    timeout: 120,
                    enabled: false
                ),
                on: owner
            )
            try await client.executeScheduledTask("task-1", on: owner)
            try await client.deleteScheduledTask("task-1", from: owner)
        }
    }

    func testCreateOmitsContainerWhenNil() throws {
        let data = try CoolifyJSON.encoder().encode(
            ScheduledTaskDraft(name: "Ping", command: "true", frequency: "weekly")
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["container"])
        XCTAssertNil(object["timeout"])
        XCTAssertNil(object["enabled"])
        XCTAssertEqual(object["name"] as? String, "Ping")
        XCTAssertEqual(object["command"] as? String, "true")
        XCTAssertEqual(object["frequency"] as? String, "weekly")
        XCTAssertEqual(object.count, 3)
    }

    func testDecodesEnabledAsOne() throws {
        let task = try CoolifyJSON.decoder().decode(
            ScheduledTask.self,
            from: Data(
                (#"{"id":7,"uuid":"task-1","enabled":1,"name":"Cleanup","command":"echo ok","#
                    + #""frequency":"daily","timeout":"300"}"#).utf8
            )
        )
        XCTAssertEqual(task.id, 7)
        XCTAssertEqual(task.uuid, "task-1")
        XCTAssertEqual(task.enabled, true)
        XCTAssertEqual(task.name, "Cleanup")
        XCTAssertEqual(task.timeout, 300)
        XCTAssertNil(task.container)

        let execution = try CoolifyJSON.decoder().decode(
            ScheduledTaskExecution.self,
            from: Data(
                #"{"uuid":"run-1","status":"failed","retry_count":"2","duration":1.5,"message":"nope"}"#.utf8)
        )
        XCTAssertEqual(execution.status, "failed")
        XCTAssertEqual(execution.retryCount, 2)
        XCTAssertEqual(execution.duration, 1.5)
        XCTAssertEqual(execution.message, "nope")
    }
}

/// URLSession hands a protocol the body as a stream, not as `httpBody`.
private func scheduledTaskBody(_ request: URLRequest) -> String? {
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

private func makeScheduledTaskClient(
    responder: @escaping @Sendable (URLRequest) throws -> (Int, Data, [String: String])
) throws -> CoolifyClient {
    ScheduledTaskURLProtocol.responder = responder
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ScheduledTaskURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return try CoolifyClient(instanceURL: "http://coolify.example:8000", token: "test-token", session: session)
}

private final class ScheduledTaskURLProtocol: URLProtocol, @unchecked Sendable {
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

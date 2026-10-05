import Foundation
import XCTest

@testable import CoolifyAPI

final class StorageTests: XCTestCase {
    func testListsStoragesAsTwoArrays() async throws {
        let fixture = """
            {
              "persistent_storages": [
                {
                  "uuid": "vol-1",
                  "name": "data",
                  "mount_path": "/var/lib/data",
                  "is_directory": 0,
                  "ignored": true,
                  "backup": {
                    "uuid": "bak-1",
                    "message": "Schedule saved.",
                    "storage_uuid": "vol-1",
                    "storage_type": "persistent",
                    "frequency": "daily",
                    "enabled": 1,
                    "save_s3": 0,
                    "stop_during_backup": 0
                  }
                }
              ],
              "file_storages": [
                {
                  "uuid": "file-1",
                  "mount_path": "/etc/app/config",
                  "content": "port=80",
                  "is_directory": 1,
                  "fs_path": "/host/config"
                }
              ]
            }
            """
        let client = try makeStorageClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/applications/app-1/storages")
            return (200, Data(fixture.utf8), [:])
        }
        let storages = try await client.storages(of: .application("app-1"))
        XCTAssertEqual(storages.map(\.uuid), ["vol-1", "file-1"])
        XCTAssertEqual(storages[0].kind, .persistent)
        XCTAssertEqual(storages[0].name, "data")
        XCTAssertEqual(storages[0].mountPath, "/var/lib/data")
        XCTAssertFalse(storages[0].isDirectory)
        XCTAssertEqual(storages[0].backup?.frequency, "daily")
        XCTAssertEqual(storages[0].backup?.enabled, true)
        XCTAssertEqual(storages[0].backup?.saveS3, false)
        XCTAssertEqual(storages[1].kind, .file)
        XCTAssertTrue(storages[1].isDirectory)
        XCTAssertEqual(storages[1].fsPath, "/host/config")
        XCTAssertEqual(storages[1].content, "port=80")
    }

    func testListsStoragesAsABareArray() async throws {
        let fixture = """
            [{"uuid":"vol-2","type":"file","mount_path":"/etc/hosts","is_directory":0,"fs_path":"/etc/hosts"}]
            """
        let client = try makeStorageClient { request in
            XCTAssertEqual(request.url?.path, "/api/v1/databases/db-1/storages")
            return (200, Data(fixture.utf8), [:])
        }
        let storages = try await client.storages(of: .database("db-1"))
        XCTAssertEqual(storages.count, 1)
        XCTAssertEqual(storages[0].kind, .file)
        XCTAssertFalse(storages[0].isDirectory)
    }

    func testCreatesPersistentAndDirectoryStorage() async throws {
        let client = try makeStorageClient { request in
            let body = try jsonObject(request)
            if body["type"] as? String == "persistent" {
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/api/v1/applications/app-1/storages")
                XCTAssertEqual(body["name"] as? String, "data")
                XCTAssertEqual(body["mount_path"] as? String, "/var/lib/data")
                XCTAssertNil(body["content"])
                XCTAssertNil(body["is_directory"])
                XCTAssertNil(body["fs_path"])
                return (
                    201, Data(#"{"uuid":"vol-1","type":"persistent","name":"data","mount_path":"/var/lib/data"}"#.utf8),
                    [:])
            }
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/services/svc-1/storages")
            XCTAssertEqual(body["type"] as? String, "file")
            XCTAssertEqual(body["mount_path"] as? String, "/mnt/config")
            XCTAssertEqual(body["fs_path"] as? String, "/host/config")
            XCTAssertEqual(storageFlag(body["is_directory"]), true)
            XCTAssertNil(body["name"])
            XCTAssertNil(body["content"])
            return (
                201, Data(#"{"uuid":"dir-1","type":"file","mount_path":"/mnt/config","is_directory":true}"#.utf8), [:])
        }
        let volume = try await client.createStorage(
            ResourceStorageDraft(
                type: .persistent,
                name: "data",
                mountPath: "/var/lib/data",
                content: "skip",
                isDirectory: true,
                fsPath: "/host/data"
            ),
            on: .application("app-1")
        )
        XCTAssertEqual(volume.uuid, "vol-1")
        XCTAssertEqual(volume.kind, .persistent)
        let directory = try await client.createStorage(
            ResourceStorageDraft(type: .file, mountPath: "/mnt/config", isDirectory: true, fsPath: "/host/config"),
            on: .service("svc-1")
        )
        XCTAssertEqual(directory.kind, .file)
        XCTAssertTrue(directory.isDirectory)
    }

    func testUpdatesAndDeletesStorage() async throws {
        let client = try makeStorageClient { request in
            if request.httpMethod == "PATCH" {
                XCTAssertEqual(request.url?.path, "/api/v1/applications/app-1/storages")
                let body = try jsonObject(request)
                XCTAssertEqual(body["uuid"] as? String, "vol-1")
                XCTAssertEqual(body["type"] as? String, "persistent")
                XCTAssertEqual(body["name"] as? String, "data")
                XCTAssertEqual(body["mount_path"] as? String, "/data")
                XCTAssertNil(body["content"])
                XCTAssertNil(body["is_directory"])
                XCTAssertNil(body["fs_path"])
                return (
                    200, Data(#"{"uuid":"vol-1","type":"persistent","name":"data","mount_path":"/data"}"#.utf8), [:])
            }
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/api/v1/applications/app-1/storages/vol-1")
            XCTAssertNil(storageBody(request))
            return (200, Data(#"{"message":"Storage deleted."}"#.utf8), [:])
        }
        _ = try await client.updateStorage(
            ResourceStorageDraft(
                uuid: "vol-1", type: .persistent, name: "data", mountPath: "/data", isDirectory: true, fsPath: "/host"
            ),
            on: .application("app-1")
        )
        try await client.deleteStorage("vol-1", from: .application("app-1"))
    }

    func testSetsDeletesAndRunsVolumeBackup() async throws {
        let saved = """
            {
              "uuid": "bak-1",
              "message": "Backup schedule created.",
              "storage_uuid": "vol-1",
              "storage_type": "persistent",
              "frequency": "daily",
              "enabled": true,
              "save_s3": false,
              "disable_local_backup": false,
              "stop_during_backup": true,
              "retention_amount_locally": 4,
              "retention_days_locally": 0,
              "retention_max_storage_locally": 0,
              "retention_amount_s3": 7,
              "retention_days_s3": 0,
              "retention_max_storage_s3": 0,
              "timeout": 3600
            }
            """
        let client = try makeStorageClient { request in
            let path = request.url?.path ?? ""
            if request.httpMethod == "PUT" {
                XCTAssertEqual(path, "/api/v1/databases/db-1/storages/vol-1/backups")
                let body = try jsonObject(request)
                XCTAssertEqual(body["frequency"] as? String, "daily")
                XCTAssertEqual(storageFlag(body["enabled"]), true)
                XCTAssertEqual(storageFlag(body["save_s3"]), false)
                XCTAssertEqual(storageFlag(body["stop_during_backup"]), true)
                XCTAssertEqual(storageWhole(body["retention_amount_locally"]), 4)
                XCTAssertNil(body["s3_storage_uuid"])
                XCTAssertNil(body["timeout"])
                return (201, Data(saved.utf8), [:])
            }
            if path.hasSuffix("/backups/run") {
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(path, "/api/v1/services/svc-1/storages/vol-1/backups/run")
                XCTAssertNil(storageBody(request))
                return (200, Data(#"{"message":"Storage backup queued."}"#.utf8), [:])
            }
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(path, "/api/v1/databases/db-1/storages/vol-1/backups")
            return (200, Data(), [:])
        }
        let schedule = try await client.setVolumeBackup(
            VolumeBackupScheduleRequest(
                frequency: "daily",
                enabled: true,
                saveS3: false,
                stopDuringBackup: true,
                retentionAmountLocally: 4
            ),
            storage: "vol-1",
            on: .database("db-1")
        )
        XCTAssertEqual(schedule.uuid, "bak-1")
        XCTAssertEqual(schedule.storageType, "persistent")
        XCTAssertEqual(schedule.frequency, "daily")
        XCTAssertTrue(schedule.stopDuringBackup)
        XCTAssertNil(schedule.s3StorageUuid)
        let queued = try await client.runVolumeBackup(storage: "vol-1", on: .service("svc-1"))
        XCTAssertEqual(queued.message, "Storage backup queued.")
        try await client.deleteVolumeBackup(storage: "vol-1", from: .database("db-1"))
    }
}

private func makeStorageClient(
    responder: @escaping @Sendable (URLRequest) throws -> (Int, Data, [String: String])
) throws -> CoolifyClient {
    StorageFixtureProtocol.responder = responder
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StorageFixtureProtocol.self]
    let session = URLSession(configuration: configuration)
    return try CoolifyClient(instanceURL: "http://coolify.example:8000", token: "test-token", session: session)
}

private func storageBody(_ request: URLRequest) -> String? {
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

private func storageFlag(_ value: Any?) -> Bool? {
    if let value = value as? Bool { return value }
    if let value = value as? NSNumber { return value.boolValue }
    return nil
}

private func storageWhole(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    if let value = value as? NSNumber { return value.intValue }
    return nil
}

private func jsonObject(_ request: URLRequest) throws -> [String: Any] {
    let text = try XCTUnwrap(storageBody(request))
    return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
}

private final class StorageFixtureProtocol: URLProtocol, @unchecked Sendable {
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

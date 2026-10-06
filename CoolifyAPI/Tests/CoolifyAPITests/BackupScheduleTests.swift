import Foundation
import XCTest

@testable import CoolifyAPI

final class BackupScheduleTests: XCTestCase {
    override func tearDown() {
        BackupScheduleURLProtocol.responder = nil
        super.tearDown()
    }

    func testCreateBackupOmitsUnsetFields() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/databases/database/backups")
            XCTAssertTrue(queryItems(request).isEmpty)
            XCTAssertEqual(bodyText(request), #"{"frequency":"weekly"}"#)
            return (201, Data(#"{"uuid":"backup-1","message":"Backup configuration created successfully."}"#.utf8), [:])
        }
        let created = try await client.createDatabaseBackup(
            database: "database", DatabaseBackupDraft(frequency: "weekly"))
        XCTAssertEqual(created.uuid, "backup-1")
    }

    func testUpdateBackupSendsOnlyChangedFields() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/databases/database/backups/schedule")
            XCTAssertTrue(queryItems(request).isEmpty)
            let expected = """
                {"database_backup_retention_amount_locally":4,\
                "database_backup_retention_max_storage_locally":1.5,\
                "s3_storage_uuid":"store-1","save_s3":true}
                """
            XCTAssertEqual(bodyText(request), expected)
            return (200, Data(#"{"message":"Database backup configuration updated"}"#.utf8), [:])
        }
        _ = try await client.updateDatabaseBackup(
            database: "database",
            backup: "schedule",
            DatabaseBackupDraft(
                saveS3: true,
                s3StorageUUID: "store-1",
                databaseBackupRetentionAmountLocally: 4,
                databaseBackupRetentionMaxStorageLocally: 1.5
            )
        )
    }

    func testDeleteBackupSchedule() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/api/v1/databases/database/backups/schedule")
            XCTAssertTrue(queryItems(request).isEmpty)
            XCTAssertTrue((bodyText(request) ?? "").isEmpty)
            return (200, Data(#"{"message":"Backup configuration and all executions deleted."}"#.utf8), [:])
        }
        _ = try await client.deleteDatabaseBackup(database: "database", backup: "schedule")
    }

    func testBackUpNowStillSendsOnlyTheRunFlag() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/databases/database/backups/schedule")
            XCTAssertEqual(bodyText(request), #"{"backup_now":true}"#)
            return (200, Data(#"{"message":"Database backup configuration updated"}"#.utf8), [:])
        }
        _ = try await client.backUpNow(database: "database", backup: "schedule")
    }

    func testCreateS3StorageSendsKeyAndSecret() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/s3-storages")
            // JSONEncoder writes `/` as `\/`, so compare the parsed body rather than its text.
            let body = try JSONSerialization.jsonObject(with: Data((bodyText(request) ?? "").utf8)) as? NSDictionary
            XCTAssertEqual(
                body,
                [
                    "bucket": "dumps", "endpoint": "https://s3.example.com", "key": "access-key", "name": "Backups",
                    "region": "us-east-1", "secret": "secret-value",
                ] as NSDictionary)
            return (201, Data(#"{"uuid":"store-1"}"#.utf8), [:])
        }
        let created = try await client.createS3Storage(
            S3StorageDraft(
                name: "Backups",
                endpoint: "https://s3.example.com",
                bucket: "dumps",
                region: "us-east-1",
                key: "access-key",
                secret: "secret-value"
            )
        )
        XCTAssertEqual(created.uuid, "store-1")
    }

    func testUpdateS3StorageOmitsBlankSecret() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/s3-storages/store-1")
            XCTAssertEqual(bodyText(request), #"{"name":"Backups"}"#)
            return (200, Data(#"{"uuid":"store-1"}"#.utf8), [:])
        }
        _ = try await client.updateS3Storage(
            "store-1",
            S3StorageUpdate(name: "Backups", key: " ", secret: "")
        )
    }

    func testDatabaseBackupDecodesListedShapes() throws {
        let fixture = """
            [{"uuid":"schedule","enabled":"1","frequency":"daily","save_s3":1,\
            "s3_storage_uuid":"store-1","dump_all":0,"databases_to_backup":"app",\
            "database_backup_retention_amount_locally":"7",\
            "database_backup_retention_days_locally":14,\
            "database_backup_retention_max_storage_locally":"1.5","timeout":"3600",\
            "executions":[{"uuid":"execution","status":"failed","size":"42",\
            "message":"Storage unavailable"}]}]
            """
        let backups = try CoolifyJSON.decoder().decode([DatabaseBackup].self, from: Data(fixture.utf8))
        let backup = backups[0]
        XCTAssertTrue(backup.enabled)
        XCTAssertTrue(backup.saveS3)
        XCTAssertFalse(backup.dumpAll)
        XCTAssertEqual(backup.s3StorageUUID, "store-1")
        XCTAssertEqual(backup.databaseBackupRetentionAmountLocally, 7)
        XCTAssertEqual(backup.databaseBackupRetentionDaysLocally, 14)
        XCTAssertEqual(backup.databaseBackupRetentionMaxStorageLocally, 1.5)
        XCTAssertEqual(backup.timeout, 3600)
        XCTAssertEqual(backup.executions[0].size, 42)
        XCTAssertEqual(backup.id, "schedule")
    }

    func testS3StorageDecodesFlexibleFlags() throws {
        let json =
            #"{"uuid":"store-1","name":"Backups","description":null,"endpoint":"https://s3.example.com","#
            + #""bucket":"dumps","region":"us-east-1","is_usable":0,"team_id":1,"#
            + #""created_at":"2026-09-01T00:00:00Z","updated_at":"2026-09-01T00:00:00Z"}"#
        let storage = try CoolifyJSON.decoder().decode(S3Storage.self, from: Data(json.utf8))
        XCTAssertEqual(storage.id, "store-1")
        XCTAssertEqual(storage.name, "Backups")
        XCTAssertNil(storage.description)
        XCTAssertEqual(storage.bucket, "dumps")
        XCTAssertFalse(storage.isUsable)
    }
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
    BackupScheduleURLProtocol.responder = responder
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [BackupScheduleURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return try CoolifyClient(instanceURL: "http://coolify.example:8000", token: "test-token", session: session)
}

/// Answers backup and S3 requests in tests. Not the suite's shared mock.
private final class BackupScheduleURLProtocol: URLProtocol, @unchecked Sendable {
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

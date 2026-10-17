import Foundation
import XCTest

@testable import CoolifyAPI

final class DatabaseImportTests: XCTestCase {
    private var files: [URL] = []

    override func tearDown() {
        DatabaseImportURLProtocol.responder = nil
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
        files = []
        super.tearDown()
    }

    // MARK: Upload

    func testUploadSendsDropzoneChunksAndReturnsTheStoredFile() async throws {
        let file = try makeFile("backup.sql.gz", bytes: Array("0123456789".utf8))
        let requests = RequestLog()
        let client = try makeClient { request in
            let parts = multipart(request)
            requests.append(parts)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/databases/db-1/imports/uploads")
            XCTAssertTrue(
                request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            if parts.fields["dzchunkindex"] == "2" {
                return (
                    201,
                    Data(
                        #"{"upload_id":"up-1","filename":"backup.sql.gz","mime_type":"application/gzip","size":"10"}"#
                            .utf8),
                    [:]
                )
            }
            return (200, Data(#"{"upload_id":"up-1","done":33,"status":true}"#.utf8), [:])
        }
        let progress = ProgressLog()

        let upload = try await client.uploadDatabaseImport(
            .database("db-1"), file: file, uploadID: "up-1", chunkSize: 4, progress: { progress.append($0) })

        XCTAssertEqual(
            upload,
            DatabaseImportUpload(uploadID: "up-1", filename: "backup.sql.gz", mimeType: "application/gzip", size: 10))
        XCTAssertEqual(progress.values.map(\.sentBytes), [4, 8, 10])
        XCTAssertEqual(progress.values.last?.fraction, 1)

        let chunks = requests.values
        XCTAssertEqual(chunks.count, 3)
        for (index, chunk) in chunks.enumerated() {
            XCTAssertEqual(chunk.fields["upload_id"], "up-1")
            XCTAssertEqual(chunk.fields["dzuuid"], "up-1")
            XCTAssertEqual(chunk.fields["dzchunkindex"], String(index))
            XCTAssertEqual(chunk.fields["dztotalchunkcount"], "3")
            XCTAssertEqual(chunk.fields["dzchunksize"], "4")
            XCTAssertEqual(chunk.fields["dztotalfilesize"], "10")
            XCTAssertEqual(chunk.fields["dzTotalFilesize"], "10")
            XCTAssertEqual(chunk.fields["dzchunkbyteoffset"], String(index * 4))
            XCTAssertEqual(chunk.filename, "backup.sql.gz")
        }
        XCTAssertEqual(chunks.map(\.file), ["0123", "4567", "89"])
    }

    func testServiceDatabaseUploadEncodesBothUUIDs() async throws {
        let file = try makeFile("dump.sql", bytes: Array("select 1;".utf8))
        let client = try makeClient { request in
            XCTAssertEqual(
                request.url?.absoluteString,
                "http://coolify.example:8000/api/v1/services/svc%201/databases/db%2F2/imports/uploads")
            return (
                201, Data(#"{"upload_id":"up-2","filename":"dump.sql","mime_type":"text/plain","size":9}"#.utf8), [:]
            )
        }

        let upload = try await client.uploadDatabaseImport(
            .serviceDatabase(service: "svc 1", database: "db/2"), file: file, uploadID: "up-2")

        XCTAssertEqual(upload.uploadID, "up-2")
        XCTAssertEqual(upload.size, 9)
    }

    func testUploadRefusesNamesAndSizesBeforeSending() async throws {
        let client = try makeClient { request in
            XCTFail("No request expected, got \(request.url?.absoluteString ?? "")")
            return (500, Data(), [:])
        }
        let script = try makeFile("backup.php.sql", bytes: Array("x".utf8))
        let empty = try makeFile("empty.sql", bytes: [])

        await assertThrows(try await client.uploadDatabaseImport(.database("db"), file: script)) { error in
            XCTAssertEqual((error as? CoolifyError)?.message, "Coolify does not accept a backup named backup.php.sql.")
        }
        await assertThrows(try await client.uploadDatabaseImport(.database("db"), file: empty)) { error in
            XCTAssertEqual((error as? CoolifyError)?.message, "The backup file is empty.")
        }
    }

    func testUploadStopsAtTheFirstRejectedChunk() async throws {
        let file = try makeFile("backup.dump", bytes: Array("PGDMP-not-really".utf8))
        let requests = RequestLog()
        let client = try makeClient { request in
            requests.append(multipart(request))
            let body = #"{"message":"Validation failed.","errors":{"file":["Unsupported backup file extension."]}}"#
            return (422, Data(body.utf8), [:])
        }

        await assertThrows(try await client.uploadDatabaseImport(.database("db"), file: file, chunkSize: 4)) { error in
            let error = error as? CoolifyError
            XCTAssertEqual(error?.isValidation, true)
            XCTAssertEqual(error?.summary, "Validation failed. Unsupported backup file extension.")
        }
        XCTAssertEqual(requests.values.count, 1)
    }

    func testUploadFailsWhenTheLastChunkIsNotAcceptedAsComplete() async throws {
        let file = try makeFile("backup.sql", bytes: Array("select 1;".utf8))
        let client = try makeClient { _ in
            (200, Data(#"{"upload_id":"up","done":50,"status":true}"#.utf8), [:])
        }

        await assertThrows(try await client.uploadDatabaseImport(.database("db"), file: file)) { error in
            XCTAssertEqual(
                (error as? CoolifyError)?.message, "Coolify did not finish receiving the backup. Try the upload again.")
        }
    }

    func testUploadOnACoolifyWithoutImportsIsNotFound() async throws {
        let file = try makeFile("backup.sql", bytes: Array("select 1;".utf8))
        let client = try makeClient { _ in (404, Data(#"{"message":"Not found."}"#.utf8), [:]) }

        await assertThrows(try await client.uploadDatabaseImport(.database("db"), file: file)) { error in
            XCTAssertEqual((error as? CoolifyError)?.isNotFound, true)
        }
    }

    func testUploadRetriesAChunkWhoseConnectionDropped() async throws {
        let file = try makeFile("backup.sql", bytes: Array("select 1;".utf8))
        let attempts = RequestLog()
        let client = try makeClient { request in
            attempts.append(multipart(request))
            if attempts.values.count == 1 { throw URLError(.networkConnectionLost) }
            return (201, Data(#"{"upload_id":"up","filename":"backup.sql","size":9}"#.utf8), [:])
        }

        let upload = try await client.uploadDatabaseImport(.database("db"), file: file, uploadID: "up")

        XCTAssertEqual(upload.uploadID, "up")
        XCTAssertEqual(attempts.values.map(\.file), ["select 1;", "select 1;"])
    }

    // MARK: Start

    func testStartImportFromUploadSendsOnlyItsKeysAndTheFlagsThatAreOn() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/databases/db-1/imports")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(bodyText(request), #"{"dump_all":true,"source":"upload","upload_id":"up-1"}"#)
            let body = """
                {"id":42,"status":"queued","message":"Database import queued.",\
                "status_url":"/api/v1/databases/db-1/imports/42"}
                """
            return (202, Data(body.utf8), ["Location": "/api/v1/databases/db-1/imports/42"])
        }

        let queued = try await client.startDatabaseImport(
            .database("db-1"), source: .upload("up-1"), options: DatabaseImportOptions(dumpAll: true))

        XCTAssertEqual(queued.id, 42)
        XCTAssertEqual(queued.phase, .queued)
        XCTAssertEqual(queued.message, "Database import queued.")
    }

    func testStartImportFromS3AndServerPaths() async throws {
        let bodies = BodyLog()
        let client = try makeClient { request in
            XCTAssertEqual(request.url?.path, "/api/v1/services/svc/databases/db/imports")
            bodies.append(try JSONSerialization.jsonObject(with: Data((bodyText(request) ?? "").utf8)) as? NSDictionary)
            // The id arrives as text, and the status is still unset on a fresh activity.
            return (202, Data(#"{"id":"7","status":null}"#.utf8), [:])
        }
        let target = DatabaseImportTarget.serviceDatabase(service: "svc", database: "db")

        let fromS3 = try await client.startDatabaseImport(
            target, source: .s3(storage: "3", path: "data/coolify/backups/pg.dmp"),
            options: DatabaseImportOptions(replaceExisting: true, keepOwners: true))
        _ = try await client.startDatabaseImport(
            target, source: .server(path: "/data/coolify/backups/app.db.gz"),
            options: DatabaseImportOptions(restoreMySQLUsers: true, sqliteDatabase: "  app.db "))

        XCTAssertEqual(fromS3.id, 7)
        XCTAssertEqual(fromS3.phase, .queued)
        XCTAssertEqual(
            bodies.values,
            [
                [
                    "source": "s3", "s3_storage_uuid": "3", "path": "data/coolify/backups/pg.dmp",
                    "replace_existing": true, "keep_owners": true,
                ],
                [
                    "source": "server", "path": "/data/coolify/backups/app.db.gz", "restore_mysql_users": true,
                    "sqlite_database": "app.db",
                ],
            ]
        )
    }

    func testStartImportConflictIsReported() async throws {
        let client = try makeClient { _ in
            (409, Data(#"{"message":"A database import is already running."}"#.utf8), [:])
        }

        await assertThrows(try await client.startDatabaseImport(.database("db"), source: .upload("up"))) { error in
            let error = error as? CoolifyError
            XCTAssertEqual(error?.isConflict, true)
            XCTAssertEqual(error?.message, "A database import is already running.")
        }
    }

    func testStartImportOnAnUnsupportedEngineKeepsCoolifysMessage() async throws {
        let client = try makeClient { _ in
            (422, Data(#"{"message":"Database imports are not supported for this database type."}"#.utf8), [:])
        }

        await assertThrows(try await client.startDatabaseImport(.database("redis"), source: .upload("up"))) { error in
            XCTAssertEqual(
                (error as? CoolifyError)?.summary, "Database imports are not supported for this database type.")
        }
    }

    // MARK: Status

    func testImportStatusReadsAQueuedThenFinishedActivity() async throws {
        let replies = [
            #"{"id":42,"status":"in_progress","exit_code":null,"output":null,"created_at":"2026-10-17T08:00:00.000000Z","updated_at":"2026-10-17T08:00:03.000000Z","finished_at":null}"#,
            #"{"id":"42","status":"finished","exit_code":"0","output":"restored","created_at":"2026-10-17T08:00:00.000000Z","updated_at":"2026-10-17T08:01:00.000000Z","finished_at":"2026-10-17T08:01:00.000000Z"}"#,
        ]
        let calls = RequestLog()
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/services/svc/databases/db/imports/42")
            calls.append(Multipart())
            return (200, Data(replies[calls.values.count - 1].utf8), [:])
        }
        let target = DatabaseImportTarget.serviceDatabase(service: "svc", database: "db")

        let running = try await client.databaseImport(target, activity: 42)
        let finished = try await client.databaseImport(target, activity: 42)

        XCTAssertEqual(running.phase, .inProgress)
        XCTAssertFalse(running.isTerminal)
        XCTAssertFalse(running.succeeded)
        XCTAssertNil(running.output)
        XCTAssertNil(running.finishedAt)
        XCTAssertEqual(finished.id, 42)
        XCTAssertTrue(finished.isTerminal)
        XCTAssertTrue(finished.succeeded)
        XCTAssertEqual(finished.exitCode, 0)
        XCTAssertEqual(finished.output, "restored")
        XCTAssertEqual(finished.finishedAt, "2026-10-17T08:01:00.000000Z")
    }

    func testImportStatusPhases() throws {
        func decode(_ json: String) throws -> DatabaseImportStatus {
            try CoolifyJSON.decoder().decode(DatabaseImportStatus.self, from: Data(json.utf8))
        }
        let failed = try decode(#"{"id":1,"status":"error","exit_code":1,"output":"ERROR: relation exists"}"#)
        XCTAssertTrue(failed.isTerminal)
        XCTAssertFalse(failed.succeeded)
        // A finished activity with a failing exit code did not restore the backup.
        XCTAssertFalse(try decode(#"{"id":1,"status":"finished","exit_code":2}"#).succeeded)
        XCTAssertTrue(try decode(#"{"id":1,"status":"killed"}"#).isTerminal)
        XCTAssertTrue(try decode(#"{"id":1,"status":"closed"}"#).isTerminal)
        let unknown = try decode(#"{"id":1,"status":"paused"}"#)
        XCTAssertEqual(unknown.phase, .other("paused"))
        XCTAssertFalse(unknown.isTerminal)
        XCTAssertEqual(DatabaseImportPhase.inProgress.rawValue, "in_progress")
    }

    // MARK: Engines and files

    func testEngineFromDatabaseType() {
        XCTAssertEqual(DatabaseImportEngine(databaseType: "standalone-postgresql"), .postgresql)
        XCTAssertEqual(DatabaseImportEngine(databaseType: "standalone-mariadb"), .mariadb)
        XCTAssertEqual(DatabaseImportEngine(databaseType: "standalone-mysql"), .mysql)
        XCTAssertEqual(DatabaseImportEngine(databaseType: "standalone-mongodb"), .mongodb)
        XCTAssertEqual(DatabaseImportEngine(databaseType: "standalone-sqlite"), .sqlite)
        XCTAssertNil(DatabaseImportEngine(databaseType: "standalone-redis"))
        XCTAssertNil(DatabaseImportEngine(databaseType: "standalone-clickhouse"))
        XCTAssertNil(DatabaseImportEngine(databaseType: nil))
    }

    func testEngineFromServiceImage() {
        XCTAssertEqual(DatabaseImportEngine(serviceImage: "postgres:16-alpine"), .postgresql)
        XCTAssertEqual(DatabaseImportEngine(serviceImage: "timescale/timescaledb:latest-pg16"), .postgresql)
        XCTAssertEqual(DatabaseImportEngine(serviceImage: "postgis/postgis:16-3.4"), .postgresql)
        XCTAssertEqual(DatabaseImportEngine(serviceImage: "pgvector/pgvector:pg16"), .postgresql)
        XCTAssertEqual(DatabaseImportEngine(serviceImage: "supabase/postgres:15.1"), .postgresql)
        XCTAssertEqual(DatabaseImportEngine(serviceImage: "mariadb:11"), .mariadb)
        XCTAssertEqual(DatabaseImportEngine(serviceImage: "mysql:8.4"), .mysql)
        XCTAssertEqual(DatabaseImportEngine(serviceImage: "mongo:7"), .mongodb)
        XCTAssertNil(DatabaseImportEngine(serviceImage: "redis:7-alpine"))
        XCTAssertNil(DatabaseImportEngine(serviceImage: "clickhouse/clickhouse-server"))
        XCTAssertNil(DatabaseImportEngine(serviceImage: nil))
        // Coolify's custom type wins over the image.
        XCTAssertEqual(DatabaseImportEngine(serviceImage: "ghcr.io/acme/db:1", customType: "mysql"), .mysql)
    }

    func testAllowedBackupFileNames() {
        XCTAssertEqual(DatabaseImportFile.allowedExtension(for: "pg-dump-app-1759118400.dmp"), "dmp")
        XCTAssertEqual(DatabaseImportFile.allowedExtension(for: "backup.SQL.GZ"), "sql.gz")
        XCTAssertEqual(DatabaseImportFile.allowedExtension(for: "/tmp/mongo.archive.gz"), "archive.gz")
        XCTAssertEqual(DatabaseImportFile.allowedExtension(for: "app.sqlite3"), "sqlite3")
        XCTAssertNil(DatabaseImportFile.allowedExtension(for: "backup.txt"))
        XCTAssertNil(DatabaseImportFile.allowedExtension(for: ".sql"))
        XCTAssertNil(DatabaseImportFile.allowedExtension(for: "dump..sql"))
        XCTAssertNil(DatabaseImportFile.allowedExtension(for: "dump.php.sql"))
        XCTAssertEqual(DatabaseImportFile.maxBytes, 10_737_418_240)
    }

    // MARK: Stored backups

    func testStoredBackupSourcesFollowWhatRetentionKept() throws {
        // Coolify 4.4 lists the schedule's numeric `s3_storage_id`, and run flags as 0 and 1.
        let json = """
            [{
                "uuid": "schedule", "enabled": 1, "save_s3": 1, "s3_storage_id": 3, "dump_all": 0,
                "executions": [
                    {"uuid": "both", "status": "success", "filename": "/data/coolify/backups/pg-1.dmp",
                     "s3_uploaded": 1, "local_storage_deleted": 0, "s3_storage_deleted": 0, "database_name": "app"},
                    {"uuid": "s3-only", "status": "success", "filename": "/data/coolify/backups/pg-2.dmp",
                     "s3_uploaded": true, "local_storage_deleted": true, "s3_storage_deleted": false},
                    {"uuid": "server-only", "status": "success", "filename": "/data/coolify/backups/pg-3.dmp",
                     "s3_uploaded": 0, "local_storage_deleted": 0},
                    {"uuid": "older", "status": "success", "filename": "/data/coolify/backups/pg-4.dmp"},
                    {"uuid": "gone", "status": "success", "filename": "/data/coolify/backups/pg-5.dmp",
                     "s3_uploaded": 1, "local_storage_deleted": 1, "s3_storage_deleted": 1},
                    {"uuid": "failed", "status": "failed", "filename": "/data/coolify/backups/pg-6.dmp"}
                ]
            }]
            """
        let backup = try XCTUnwrap(
            try CoolifyJSON.decoder().decode([DatabaseBackup].self, from: Data(json.utf8)).first)
        XCTAssertEqual(backup.s3StorageID, "3")
        let sources = Dictionary(
            uniqueKeysWithValues: backup.executions.map {
                ($0.uuid, StoredBackupSources(execution: $0, backup: backup))
            })

        XCTAssertEqual(backup.executions.first?.databaseName, "app")
        XCTAssertEqual(
            sources["both"],
            StoredBackupSources(
                server: .server(path: "/data/coolify/backups/pg-1.dmp"),
                s3: .s3(storage: "3", path: "data/coolify/backups/pg-1.dmp")))
        XCTAssertEqual(
            sources["s3-only"], StoredBackupSources(s3: .s3(storage: "3", path: "data/coolify/backups/pg-2.dmp")))
        XCTAssertEqual(
            sources["server-only"], StoredBackupSources(server: .server(path: "/data/coolify/backups/pg-3.dmp")))
        // A run from before Coolify recorded `s3_uploaded` follows the schedule.
        XCTAssertNotNil(sources["older"]?.s3)
        XCTAssertEqual(sources["gone"]?.isEmpty, true)
        XCTAssertEqual(sources["failed"]?.isEmpty, true)
    }

    func testStoredBackupSourcesPreferTheStorageUUID() throws {
        let json = """
            {"uuid": "s", "save_s3": true, "s3_storage_uuid": "store-uuid", "s3_storage_id": 3,
             "executions": [{"uuid": "a", "status": "success", "filename": "/backups/a.sql", "s3_uploaded": true}]}
            """
        let backup = try CoolifyJSON.decoder().decode(DatabaseBackup.self, from: Data(json.utf8))
        let execution = try XCTUnwrap(backup.executions.first)

        XCTAssertEqual(
            StoredBackupSources(execution: execution, backup: backup).s3,
            .s3(storage: "store-uuid", path: "backups/a.sql"))
    }

    // MARK: Helpers

    private func makeFile(_ name: String, bytes: [UInt8]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hotify-import-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        files.append(directory)
        return url
    }

    private func assertThrows<T>(
        _ expression: @autoclosure () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ check: (Error) -> Void
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected an error", file: file, line: line)
        } catch {
            check(error)
        }
    }
}

/// One multipart request, read back into its fields and its file part.
private struct Multipart: Sendable {
    var fields: [String: String] = [:]
    var filename: String?
    var file: String?
}

private func multipart(_ request: URLRequest) -> Multipart {
    guard let contentType = request.value(forHTTPHeaderField: "Content-Type"),
        let boundary = contentType.components(separatedBy: "boundary=").last,
        let body = bodyText(request)
    else { return Multipart() }
    var result = Multipart()
    for part in body.components(separatedBy: "--\(boundary)") {
        guard let split = part.range(of: "\r\n\r\n") else { continue }
        let headers = String(part[..<split.lowerBound])
        var value = String(part[split.upperBound...])
        // "\r\n" is one Character in Swift.
        if value.hasSuffix("\r\n") { value.removeLast() }
        guard let name = headers.firstMatch(of: /name="([^"]+)"/)?.1 else { continue }
        if let filename = headers.firstMatch(of: /filename="([^"]+)"/)?.1 {
            result.filename = String(filename)
            result.file = value
        } else {
            result.fields[String(name)] = value
        }
    }
    return result
}

private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Multipart] = []
    func append(_ value: Multipart) { lock.withLock { stored.append(value) } }
    var values: [Multipart] { lock.withLock { stored } }
}

private final class BodyLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [NSDictionary] = []
    func append(_ value: NSDictionary?) { lock.withLock { stored.append(value ?? [:]) } }
    var values: [NSDictionary] { lock.withLock { stored } }
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [DatabaseImportProgress] = []
    func append(_ value: DatabaseImportProgress) { lock.withLock { stored.append(value) } }
    var values: [DatabaseImportProgress] { lock.withLock { stored } }
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

private func makeClient(
    responder: @escaping @Sendable (URLRequest) throws -> (Int, Data, [String: String])
) throws -> CoolifyClient {
    DatabaseImportURLProtocol.responder = responder
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DatabaseImportURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return try CoolifyClient(instanceURL: "http://coolify.example:8000", token: "test-token", session: session)
}

/// Answers database import requests in tests. Not the suite's shared mock.
private final class DatabaseImportURLProtocol: URLProtocol, @unchecked Sendable {
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

import Foundation

extension CoolifyClient {
    /// Uploads a backup file for an import, one chunk at a time, and returns once Coolify has the whole file.
    ///
    /// Coolify 4.4 receives uploads with the Dropzone chunk protocol, the same one its own import form sends. Only one
    /// chunk is in memory at a time. `progress` runs after each chunk. Each chunk is tried up to three times when the
    /// connection fails, which is safe because Coolify stores each chunk under its index.
    /// The file name, from `filename` or else `file`, must have an extension Coolify accepts.
    public func uploadDatabaseImport(
        _ target: DatabaseImportTarget,
        file: URL,
        filename: String? = nil,
        uploadID: String = UUID().uuidString.lowercased(),
        chunkSize: Int = DatabaseImportFile.chunkSize,
        progress: @escaping @Sendable (DatabaseImportProgress) -> Void = { _ in }
    ) async throws -> DatabaseImportUpload {
        let name = filename ?? file.lastPathComponent
        guard DatabaseImportFile.allowedExtension(for: name) != nil else {
            throw CoolifyError(message: "Coolify does not accept a backup named \(name).")
        }
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: file)
        } catch {
            throw CoolifyError(message: "The backup file could not be read.")
        }
        defer { try? handle.close() }
        let total = Int64(try handle.seekToEnd())
        guard total > 0 else { throw CoolifyError(message: "The backup file is empty.") }
        guard total <= DatabaseImportFile.maxBytes else {
            throw CoolifyError(message: "The backup is larger than Coolify's 10 GiB limit.")
        }
        let size = Int64(max(1, chunkSize))
        let chunkCount = Int((total + size - 1) / size)
        let path = target.importsPath + "/uploads"

        for index in 0..<chunkCount {
            try Task.checkCancellation()
            let offset = Int64(index) * size
            try handle.seek(toOffset: UInt64(offset))
            guard let chunk = try handle.read(upToCount: Int(min(size, total - offset))), !chunk.isEmpty else {
                throw CoolifyError(message: "The backup file changed while it was uploading.")
            }
            var form = MultipartForm()
            form.addField("upload_id", uploadID)
            form.addField("dzuuid", uploadID)
            form.addField("dzchunkindex", String(index))
            form.addField("dztotalchunkcount", String(chunkCount))
            form.addField("dzchunksize", String(size))
            form.addField("dztotalfilesize", String(total))
            // Coolify 4.4 checks the 10 GiB limit against this camelCase key before it stores a chunk, while the
            // chunk handler reads the lowercase one. Dropzone sends only the lowercase key, so both go.
            form.addField("dzTotalFilesize", String(total))
            form.addField("dzchunkbyteoffset", String(offset))
            form.addFile("file", filename: name, data: chunk)
            form.finish()

            let (data, response) = try await sendChunk(path, form: form)
            let sent = offset + Int64(chunk.count)
            progress(DatabaseImportProgress(sentBytes: sent, totalBytes: total))
            guard index == chunkCount - 1 else { continue }
            // A finished upload answers 201 with the stored file. A 200 on the last chunk means Coolify is still
            // missing a chunk.
            guard response.statusCode == 201 else {
                throw CoolifyError(
                    statusCode: response.statusCode,
                    message: "Coolify did not finish receiving the backup. Try the upload again.",
                    responseBody: String(decoding: data.prefix(2_000), as: UTF8.self)
                )
            }
            var upload = try decode(DatabaseImportUpload.self, from: data, response: response)
            if upload.uploadID.isEmpty { upload.uploadID = uploadID }
            return upload
        }
        throw CoolifyError(message: "The backup file is empty.")
    }

    /// Queues an import. Coolify answers 409 while another import, start, or restart of the database runs.
    ///
    /// Only the keys of `source` and the options that are on are sent.
    public func startDatabaseImport(
        _ target: DatabaseImportTarget,
        source: DatabaseImportSource,
        options: DatabaseImportOptions = DatabaseImportOptions()
    ) async throws -> QueuedDatabaseImport {
        try await post(target.importsPath, body: DatabaseImportRequest(source: source, options: options))
    }

    /// Reads an import activity. Coolify leaves `output` out unless the token may read sensitive data.
    public func databaseImport(_ target: DatabaseImportTarget, activity: Int) async throws -> DatabaseImportStatus {
        try await get("\(target.importsPath)/\(activity)")
    }

    private func sendChunk(_ path: String, form: MultipartForm) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        while true {
            do {
                return try await postMultipart(path, form: form)
            } catch let error as CoolifyError where error.statusCode == nil && attempt < 2 {
                // A dropped connection has no status. Anything Coolify answered is final.
                attempt += 1
                try await Task.sleep(for: .seconds(attempt * 2))
            }
        }
    }
}

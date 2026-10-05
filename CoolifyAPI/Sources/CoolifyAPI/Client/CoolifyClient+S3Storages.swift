import Foundation

extension CoolifyClient {
    /// Lists the team's S3-compatible backup stores. The response does not include the access key or the secret.
    public func s3Storages() async throws -> [S3Storage] {
        try await getList("s3-storages")
    }

    public func createS3Storage(_ draft: S3StorageDraft) async throws -> CreatedResource {
        try await post("s3-storages", body: draft)
    }

    public func updateS3Storage(_ uuid: String, _ update: S3StorageUpdate) async throws -> CreatedResource {
        try await patch("s3-storages/\(CoolifyURL.encodePathComponent(uuid))", body: update)
    }

    public func deleteS3Storage(_ uuid: String) async throws -> QueuedAction {
        try await delete("s3-storages/\(CoolifyURL.encodePathComponent(uuid))")
    }

    /// Asks Coolify to list the bucket and report whether the store answers.
    public func validateS3Storage(_ uuid: String) async throws -> S3StorageValidation {
        try await post("s3-storages/\(CoolifyURL.encodePathComponent(uuid))/validate")
    }
}

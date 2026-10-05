import Foundation

extension CoolifyClient {
    public func s3Storages() async throws -> [S3Storage] {
        try await getList("s3-storages")
    }
}

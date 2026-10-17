import Foundation

/// A backup file Coolify received in full and stored for an import.
public struct DatabaseImportUpload: Decodable, Sendable, Hashable {
    public var uploadID: String
    public var filename: String?
    public var mimeType: String?
    public var size: Int64?

    enum CodingKeys: String, CodingKey {
        // `upload_id` becomes `uploadId` after snake_case conversion.
        case uploadId
        case filename
        case mimeType
        case size
    }

    public init(uploadID: String, filename: String? = nil, mimeType: String? = nil, size: Int64? = nil) {
        self.uploadID = uploadID
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uploadID = container.flexString(.uploadId) ?? ""
        filename = container.flexString(.filename)
        mimeType = container.flexString(.mimeType)
        size = container.flexInt(.size).map(Int64.init)
    }
}

/// How much of a backup has reached Coolify.
public struct DatabaseImportProgress: Sendable, Hashable {
    public var sentBytes: Int64
    public var totalBytes: Int64

    public init(sentBytes: Int64, totalBytes: Int64) {
        self.sentBytes = sentBytes
        self.totalBytes = totalBytes
    }

    public var fraction: Double {
        totalBytes > 0 ? min(1, Double(sentBytes) / Double(totalBytes)) : 0
    }
}

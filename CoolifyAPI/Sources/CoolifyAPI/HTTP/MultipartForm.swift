import Foundation

/// A `multipart/form-data` body of text fields and at most one file part, built in memory.
///
/// Keep the file part small, such as one chunk of an upload.
struct MultipartForm {
    let boundary: String
    private(set) var body = Data()

    init(boundary: String = "HotifyBoundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(_ name: String, _ value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(Self.escape(name))\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func addFile(
        _ name: String, filename: String, contentType: String = "application/octet-stream", data: Data
    ) {
        append("--\(boundary)\r\n")
        append(
            "Content-Disposition: form-data; name=\"\(Self.escape(name))\"; filename=\"\(Self.escape(filename))\"\r\n")
        append("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        append("\r\n")
    }

    /// Ends the form. Add nothing after this.
    mutating func finish() {
        append("--\(boundary)--\r\n")
    }

    private mutating func append(_ text: String) {
        body.append(Data(text.utf8))
    }

    /// A quote or a line break would end the header early.
    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\"", with: "%22")
    }
}

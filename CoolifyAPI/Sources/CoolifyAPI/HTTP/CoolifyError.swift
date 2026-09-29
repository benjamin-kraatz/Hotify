import Foundation

public struct CoolifyError: Error, Sendable, Equatable {
    public var statusCode: Int?
    public var message: String
    public var fieldErrors: [String: [String]]
    public var retryAfter: TimeInterval?
    /// A short slice of the response body, useful when Coolify's JSON does not match the client.
    public var responseBody: String?

    public init(
        statusCode: Int? = nil,
        message: String,
        fieldErrors: [String: [String]] = [:],
        retryAfter: TimeInterval? = nil,
        responseBody: String? = nil
    ) {
        self.statusCode = statusCode
        self.message = message
        self.fieldErrors = fieldErrors
        self.retryAfter = retryAfter
        self.responseBody = responseBody
    }

    public var isUnauthenticated: Bool {
        statusCode == 401
    }

    public var isNotFound: Bool {
        statusCode == 404
    }

    public var isValidation: Bool {
        statusCode == 422
    }

    static func invalidInstanceURL(_ message: String) -> CoolifyError {
        CoolifyError(message: message)
    }

    static func transport(_ message: String) -> CoolifyError {
        CoolifyError(message: message)
    }
}

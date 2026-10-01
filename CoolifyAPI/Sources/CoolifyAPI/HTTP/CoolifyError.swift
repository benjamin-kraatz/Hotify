import Foundation

public struct CoolifyError: Error, LocalizedError, Sendable, Equatable {
    public var statusCode: Int?
    public var message: String
    public var fieldErrors: [String: [String]]
    public var retryAfter: TimeInterval?
    /// A short slice of the response body, useful when Coolify's JSON does not match the client.
    public var responseBody: String?
    /// Domains already taken by other resources, sent with HTTP 409 when a service asks for them.
    public var conflicts: [DomainConflict]

    public init(
        statusCode: Int? = nil,
        message: String,
        fieldErrors: [String: [String]] = [:],
        retryAfter: TimeInterval? = nil,
        responseBody: String? = nil,
        conflicts: [DomainConflict] = []
    ) {
        self.statusCode = statusCode
        self.message = message
        self.fieldErrors = fieldErrors
        self.retryAfter = retryAfter
        self.responseBody = responseBody
        self.conflicts = conflicts
    }

    public var isUnauthenticated: Bool {
        statusCode == 401
    }

    /// The token is valid but lacks the ability, such as `write`, that the request needs.
    public var isForbidden: Bool {
        statusCode == 403
    }

    public var isNotFound: Bool {
        statusCode == 404
    }

    public var isValidation: Bool {
        statusCode == 422
    }

    public var errorDescription: String? {
        message
    }

    /// The message, followed by each validation error when Coolify only said "Validation failed."
    public var summary: String {
        let details = fieldErrors.keys.sorted().flatMap { fieldErrors[$0] ?? [] }
        guard !details.isEmpty else { return message }
        return ([message] + details).joined(separator: " ")
    }

    static func invalidInstanceURL(_ message: String) -> CoolifyError {
        CoolifyError(message: message)
    }

    static func transport(_ message: String) -> CoolifyError {
        CoolifyError(message: message)
    }
}

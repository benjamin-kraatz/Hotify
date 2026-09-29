import Foundation

/// Client for one Coolify 4.3.x instance.
///
/// Create one client per saved instance. The token is team-scoped, so a second team is a second client.
public struct CoolifyClient: Sendable, CustomStringConvertible {
    public let apiBaseURL: URL
    public var description: String { "CoolifyClient(\(apiBaseURL.absoluteString))" }

    let token: String
    let session: URLSession

    public init(instanceURL: URL, token: String, session: URLSession? = nil) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CoolifyError.invalidInstanceURL("API token is empty.")
        }
        self.apiBaseURL = try CoolifyURL.apiBase(from: instanceURL)
        self.token = trimmed
        self.session = session ?? Self.makeSession()
    }

    public init(instanceURL: String, token: String, session: URLSession? = nil) throws {
        guard let url = URL(string: instanceURL) else {
            throw CoolifyError.invalidInstanceURL("Instance URL could not be read.")
        }
        try self.init(instanceURL: url, token: token, session: session)
    }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    /// Yields immediately, then again after each interval, until the consumer stops iterating.
    ///
    /// A thrown error ends the stream. Call the read methods directly for a one-off refresh.
    public func poll<T: Sendable>(
        every interval: Duration = .seconds(5),
        _ operation: @escaping @Sendable (CoolifyClient) async throws -> T
    ) -> AsyncThrowingStream<T, Error> {
        let client = self
        return AsyncThrowingStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    do {
                        continuation.yield(try await operation(client))
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                    do {
                        try await Task.sleep(for: interval)
                    } catch {
                        continuation.finish()
                        return
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    static func flag(_ value: Bool) -> String {
        value ? "1" : "0"
    }

    func applicationPath(_ uuid: String) -> String {
        "applications/\(CoolifyURL.encodePathComponent(uuid))"
    }
}

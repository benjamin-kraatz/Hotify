import Foundation

/// Loads Coolify's one-click service catalog.
///
/// The Coolify API has no endpoint that lists templates. Every instance reads this same public file from Coolify's
/// CDN and creates a service by its slug, so Hotify reads it too. The request carries no token.
public struct ServiceTemplateFeed: Sendable {
    public static let defaultURL = URL(string: "https://cdn.coollabs.io/coolify/service-templates-latest.json")!

    private let url: URL
    private let session: URLSession

    public init(url: URL = Self.defaultURL, session: URLSession? = nil) {
        self.url = url
        self.session = session ?? CoolifyClient.makeSession()
    }

    /// The raw feed, for a caller that keeps a copy for the next launch.
    public func fetch() async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw CoolifyError(
                message: "Coolify's template catalog could not be reached. \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode
            throw CoolifyError(statusCode: status, message: "Coolify's template catalog is unavailable right now.")
        }
        return data
    }

    public func templates() async throws -> [ServiceTemplate] {
        try Self.templates(from: try await fetch())
    }

    /// Reads a feed, sorted by slug. A template whose entry does not decode is skipped, not fatal.
    public static func templates(from data: Data) throws -> [ServiceTemplate] {
        let entries: [String: LenientEntry]
        do {
            // A plain decoder: snake_case conversion would also rewrite slugs, which are dictionary keys.
            entries = try JSONDecoder().decode([String: LenientEntry].self, from: data)
        } catch {
            throw CoolifyError(message: "Coolify's template catalog came back in a shape Hotify can't read.")
        }
        return entries.compactMap { slug, entry in entry.value?.template(slug: slug) }
            .sorted { $0.slug < $1.slug }
    }
}

private struct LenientEntry: Decodable {
    var value: ServiceTemplateEntry?

    init(from decoder: Decoder) throws {
        value = try? ServiceTemplateEntry(from: decoder)
    }
}

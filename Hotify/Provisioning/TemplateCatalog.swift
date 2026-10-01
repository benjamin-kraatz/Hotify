import CoolifyAPI
import Foundation

/// Coolify's one-click templates, kept for the whole app. Templates do not depend on the instance.
///
/// The last feed is kept in Caches, so the gallery opens full and refreshes behind it. The feed holds no secrets.
@Observable
final class TemplateCatalog {
    var templates: [ServiceTemplate] = [] {
        didSet { shelves = TemplateShelf.group(templates) }
    }
    private(set) var shelves: [TemplateShelf] = []
    var isLoading = false
    var loadError: String?
    private(set) var refreshedAt: Date?

    /// Coolify's CDN lets the file go stale after ten minutes. A few hours is plenty for a catalog.
    private static let maxAge: TimeInterval = 6 * 3600

    /// Templates passed in count as fresh, so a preview never reaches the network.
    init(templates: [ServiceTemplate] = []) {
        self.templates = templates
        shelves = TemplateShelf.group(templates)
        refreshedAt = templates.isEmpty ? nil : .now
    }

    /// Fills the catalog from the cached copy at once, then from the network if that copy is old or missing.
    func load() async {
        if templates.isEmpty, let cached = await Self.readCache() {
            templates = cached.templates
            refreshedAt = cached.date
        }
        if let refreshedAt, Date.now.timeIntervalSince(refreshedAt) < Self.maxAge { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await ServiceTemplateFeed().fetch()
            let fresh = try await Task.detached { try ServiceTemplateFeed.templates(from: data) }.value
            templates = fresh
            refreshedAt = .now
            loadError = nil
            Task.detached(priority: .utility) { try? data.write(to: Self.cacheURL, options: .atomic) }
        } catch is CancellationError {
            return
        } catch {
            // A cached catalog still works. Only say so when there is nothing to show.
            loadError = templates.isEmpty ? Self.message(for: error) : nil
        }
    }

    func template(_ slug: String) -> ServiceTemplate? {
        templates.first { $0.slug == slug }
    }

    nonisolated private static var cacheURL: URL {
        URL.cachesDirectory.appending(path: "ServiceTemplates.json")
    }

    nonisolated private static func readCache() async -> (templates: [ServiceTemplate], date: Date)? {
        await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: cacheURL),
                let templates = try? ServiceTemplateFeed.templates(from: data), !templates.isEmpty
            else { return nil }
            let date = (try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return (templates, date ?? .distantPast)
        }.value
    }

    private static func message(for error: Error) -> String {
        (error as? CoolifyError)?.message ?? error.localizedDescription
    }
}

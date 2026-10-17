import CoolifyAPI
import Foundation

/// A list of things to create: popular templates, all of them, one shelf, the engines, or the other sources.
enum CatalogScope: Hashable, Identifiable {
    case popular
    case all
    case shelf(TemplateCategory)
    /// Things made from a file or an image the user brings: a compose file, a Dockerfile, or an image.
    case yourOwn
    case databases
    /// Applications built from a repository.
    case repositories

    var id: Self { self }

    var title: String {
        switch self {
        case .popular: "Popular"
        case .all: "All Templates"
        case .shelf(let category): category.title
        case .yourOwn: "Your Own"
        case .databases: "Databases"
        case .repositories: "Repositories"
        }
    }

    var systemImage: String {
        switch self {
        case .popular: "star"
        case .all: "square.grid.2x2"
        case .shelf(let category): category.systemImage
        case .yourOwn: ComposeMark.systemImage
        case .databases: "cylinder.split.1x2"
        case .repositories: "arrow.triangle.branch"
        }
    }

    /// Whether its list comes from Coolify's template catalog, which may still be loading.
    var isTemplates: Bool {
        switch self {
        case .popular, .all, .shelf: true
        case .yourOwn, .databases, .repositories: false
        }
    }

    func entries(in shelves: [TemplateShelf]) -> [CatalogEntry] {
        switch self {
        case .popular:
            let bySlug = Dictionary(
                shelves.flatMap(\.templates).map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
            return TemplateCategory.popular.compactMap { bySlug[$0] }.map(CatalogEntry.template)
        case .all:
            return shelves.flatMap(\.templates)
                .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
                .map(CatalogEntry.template)
        case .shelf(let category):
            return (shelves.first { $0.category == category }?.templates ?? []).map(CatalogEntry.template)
        case .yourOwn:
            return [.compose, .application(.dockerfile), .application(.dockerImage)]
        case .databases:
            return DatabaseEngine.allCases.map(CatalogEntry.engine)
        case .repositories:
            return [.application(.publicGit), .application(.githubApp), .application(.deployKey)]
        }
    }

    /// How many it lists, for a badge beside its title.
    func count(in shelves: [TemplateShelf]) -> Int {
        switch self {
        case .all: shelves.reduce(0) { $0 + $1.templates.count }
        case .shelf(let category): shelves.first { $0.category == category }?.templates.count ?? 0
        default: entries(in: shelves).count
        }
    }

    /// Everything that answers a search, templates and the rest together, best match first.
    static func search(_ query: String, in shelves: [TemplateShelf]) -> [CatalogEntry] {
        let templates: [CatalogEntry] = shelves.flatMap(\.templates).map(CatalogEntry.template)
        let scored: [(entry: CatalogEntry, score: Int)] = (templates + CatalogEntry.builtIn).compactMap { entry in
            guard let score = entry.searchScore(query) else { return nil }
            return (entry, score)
        }
        return scored.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            return lhs.entry.name.localizedStandardCompare(rhs.entry.name) == .orderedAscending
        }
        .map(\.entry)
    }
}

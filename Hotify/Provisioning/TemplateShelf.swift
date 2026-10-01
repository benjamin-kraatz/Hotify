import CoolifyAPI
import Foundation

/// One shelf of the gallery: a category and its templates, sorted by name.
struct TemplateShelf: Identifiable, Hashable {
    var category: TemplateCategory
    var templates: [ServiceTemplate]

    var id: TemplateCategory { category }

    /// Sorts each template's name once rather than on every comparison. The catalog groups once per refresh.
    static func group(_ templates: [ServiceTemplate]) -> [TemplateShelf] {
        let named = templates.map { (template: $0, name: $0.displayName) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let grouped = Dictionary(grouping: named.map(\.template), by: \.shelf)
        return TemplateCategory.allCases.compactMap { category in
            grouped[category].map { TemplateShelf(category: category, templates: $0) }
        }
    }
}

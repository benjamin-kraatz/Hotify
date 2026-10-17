import Foundation

/// A row in the New Resource sidebar. A list of templates or engines picks one in the middle column. A compose file
/// or an application source has no list, so its file or fields take the middle column instead.
enum ProvisioningSource: Hashable {
    case list(CatalogScope)
    case compose
    case application(NewApplicationSource)

    var title: String {
        switch self {
        case .list(let scope): scope.title
        case .compose: CatalogEntry.compose.name
        case .application(let source): source.title
        }
    }

    var systemImage: String {
        switch self {
        case .list(.databases): "cylinder.split.1x2"
        case .list(let scope): scope.systemImage
        case .compose: "square.stack.3d.up"
        case .application(let source): source.systemImage
        }
    }

    /// The source an entry belongs to when it is chosen from a search. A template or engine stays in the list it
    /// came from. The others need the middle column for their own file or fields.
    init?(choosing entry: CatalogEntry) {
        switch entry {
        case .template, .engine: return nil
        case .compose: self = .compose
        case .application(let source): self = .application(source)
        }
    }
}

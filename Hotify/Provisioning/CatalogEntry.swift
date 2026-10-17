import CoolifyAPI
import Foundation

/// One thing the New Resource sheet can create: a template, a database engine, a compose file, or an application source.
/// Lists and search show them side by side, so a search for Postgres finds the engine and the templates that use it.
enum CatalogEntry: Hashable, Identifiable {
    case template(ServiceTemplate)
    case engine(DatabaseEngine)
    case compose
    case application(NewApplicationSource)

    var id: String {
        switch self {
        case .template(let template): "template.\(template.slug)"
        case .engine(let engine): "engine.\(engine.rawValue)"
        case .compose: "compose"
        case .application(let source): "application.\(source.rawValue)"
        }
    }

    var name: String {
        switch self {
        case .template(let template): template.displayName
        case .engine(let engine): engine.displayName
        case .compose: "Compose file"
        case .application(let source): source.title
        }
    }

    var slogan: String {
        switch self {
        case .template(let template): template.slogan
        case .engine(let engine): engine.slogan
        case .compose: "Write or paste a compose file, and run it as a service."
        case .application(let source): source.slogan
        }
    }

    /// What kind of thing it is, beside its name in a list.
    var caption: String {
        switch self {
        case .template(let template): template.shelf.title
        case .engine(let engine): String(engine.port)
        case .compose: "Service"
        case .application: "Application"
        }
    }

    /// The steps it takes from here to running.
    var steps: [ProvisioningStep] {
        switch self {
        case .template, .compose: ProvisioningStep.allCases
        case .engine, .application: ProvisioningStep.instant
        }
    }

    /// The screen that creates it, pushed on iPhone.
    var route: ProvisioningRoute {
        switch self {
        case .template(let template): .template(template)
        case .engine(let engine): .database(engine)
        case .compose: .compose
        case .application(let source): .application(source)
        }
    }

    /// How well it answers a search, best first, or `nil` when it does not. Templates rank by their own score. The
    /// rest match on name, then slogan, and sort after a template that matches equally well.
    func searchScore(_ query: String) -> Int? {
        if case .template(let template) = self {
            return template.searchScore(query).map { $0 * 2 }
        }
        if name.localizedStandardContains(query) { return 1 }
        if slogan.localizedStandardContains(query) { return 7 }
        return nil
    }

    /// Every entry that is not a template, in the order the sheet lists them.
    static let builtIn: [CatalogEntry] =
        [.compose] + DatabaseEngine.allCases.map(CatalogEntry.engine)
        + NewApplicationSource.allCases.map(CatalogEntry.application)
}

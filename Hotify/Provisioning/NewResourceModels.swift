import CoolifyAPI
import Foundation

/// The three models behind the New Resource sheet, one per kind of resource. They share one placement, so a server or
/// project picked for a template is still picked after switching to a database.
struct NewResourceModels {
    var services: ProvisioningModel
    var databases: DatabaseProvisioningModel
    var applications: ApplicationProvisioningModel

    var isCreating: Bool {
        services.isCreating || databases.isCreating || applications.isCreating
    }

    /// Readies the model for what was just chosen, before its launch pad shows.
    func choose(_ entry: CatalogEntry, catalog: TemplateCatalog) {
        switch entry {
        case .template(let template):
            services.createProblem = nil
            // Keep a name the user typed. One that is a template's slug was filled in here.
            if services.name.isEmpty || catalog.template(services.name) != nil {
                services.name = template.slug
            }
        case .compose:
            services.createProblem = nil
            // A template's slug filled in for another choice is no name for this one.
            if catalog.template(services.name) != nil {
                services.name = ""
            }
        case .engine:
            databases.createProblem = nil
        case .application(let source):
            applications.createProblem = nil
            applications.source = source
        }
    }
}

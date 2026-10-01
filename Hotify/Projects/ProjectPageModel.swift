import CoolifyAPI
import Foundation

/// What the project page holds on to: the open tab, the deployment history, and the shared variables.
///
/// The window keeps one of these, not the page itself. A resource opened from the page takes its place in the
/// column, and coming back should find the page as it was left rather than loading from nothing.
@Observable
final class ProjectPageModel {
    var tab = ProjectTab.overview
    let activity: ProjectActivityModel
    let variables: SharedVariablesModel

    private var key: AnyHashable?

    init(
        activity: ProjectActivityModel = ProjectActivityModel(),
        variables: SharedVariablesModel = SharedVariablesModel()
    ) {
        self.activity = activity
        self.variables = variables
    }

    /// Points the page at a project. `key` tells one project from another, across instances too. The same key
    /// again keeps the tab and everything loaded, and only brings the environments up to date.
    func open(_ key: some Hashable, project: ProjectSummary, client: CoolifyClient) {
        let key = AnyHashable(key)
        if key != self.key {
            self.key = key
            tab = .overview
            activity.prepare(client)
            variables.prepare(client)
        }
        variables.track(project)
    }
}

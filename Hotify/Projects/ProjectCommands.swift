import SwiftUI

extension FocusedValues {
    /// Opens the New Service sheet in the project on screen. Unset everywhere but a project's own page.
    @Entry var newService: NewServiceAction?
}

/// Opens the New Service sheet in one project. Equal for the same project, so the menu does not redraw on every
/// update of the page.
struct NewServiceAction: Equatable {
    var projectID: String
    var open: () -> Void

    func callAsFunction() { open() }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.projectID == rhs.projectID }
}

/// The Project menu. New Service works while a project's page is open, and creates the service in that project.
struct ProjectCommands: Commands {
    @FocusedValue(\.newService) private var newService

    var body: some Commands {
        CommandMenu("Project") {
            // The page's toolbar button has no shortcut of its own. The menu holds it, so it fires once.
            Button("New Service…") {
                newService?()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(newService == nil)
        }
    }
}

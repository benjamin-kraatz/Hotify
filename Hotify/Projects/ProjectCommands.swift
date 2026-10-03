import SwiftUI

extension FocusedValues {
    /// Opens the New Resource sheet in the project on screen. Unset everywhere but a project's own page.
    @Entry var newService: NewServiceAction?
}

/// Opens the New Resource sheet in one project. Equal for the same project, so the menu does not redraw on every
/// update of the page.
struct NewServiceAction: Equatable {
    var projectID: String
    var open: () -> Void

    func callAsFunction() { open() }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.projectID == rhs.projectID }
}

/// The Project menu. New Resource works while a project's page is open, and creates the service or database in that
/// project.
struct ProjectCommands: Commands {
    @FocusedValue(\.newService) private var newService

    var body: some Commands {
        CommandMenu("Project") {
            // The page's toolbar button has no shortcut of its own. The menu holds it, so it fires once.
            Button("New Resource…") {
                newService?()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(newService == nil)
        }
    }
}

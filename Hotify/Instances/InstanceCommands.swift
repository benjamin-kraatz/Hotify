import SwiftUI

extension FocusedValues {
    /// Opens the form that adds an instance.
    @Entry var addInstance: AddInstanceAction?
}

/// Opens the form that adds an instance. Every one is equal, since there is only one form to open.
struct AddInstanceAction: Equatable {
    var open: () -> Void

    func callAsFunction() { open() }

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

/// File > New Instance. The sidebar's own button leaves the toolbar while the sidebar is hidden, and this stays.
struct InstanceCommands: Commands {
    @FocusedValue(\.addInstance) private var addInstance

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Instance…") {
                addInstance?()
            }
            .keyboardShortcut("n")
            .disabled(addInstance == nil)
        }
    }
}

import SwiftUI

extension EnvironmentValues {
    /// Closes the New Resource sheet from its inspector. `nil` where a toolbar holds Cancel instead.
    @Entry var provisioningCancel: ProvisioningCancel?
    /// A launch pad shown in the Mac sheet's inspector column, which wants a smaller head than a screen of its own.
    @Entry var isProvisioningInspector = false
}

/// Closes the New Resource sheet. Always equal to another, since the sheet has one way to close, so the inspector
/// does not redraw on every update of the sheet.
struct ProvisioningCancel: Equatable {
    var close: () -> Void

    func callAsFunction() { close() }

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

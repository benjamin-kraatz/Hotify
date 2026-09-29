import SwiftUI

/// The actions `ResourceAction.available(for:)` offers, as menu buttons. Stop asks first, so it carries an ellipsis.
struct ResourceActionButtons: View {
    var resource: ResourceSummary
    var pendingAction: ResourceAction?
    var onAction: (ResourceAction) -> Void

    var body: some View {
        ForEach(ResourceAction.available(for: resource)) { action in
            Button(action == .stop ? "Stop…" : action.title, systemImage: action.systemImage) {
                onAction(action)
            }
            .help(action.explanation(for: resource.kind))
            .disabled(action.isBlocked(by: pendingAction))
        }
    }
}
